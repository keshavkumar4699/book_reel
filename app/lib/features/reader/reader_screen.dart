import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../core/models/reel_card.dart';
import '../../core/segmentation/feed_builder.dart';
import '../../core/segmentation/rule_segmenter.dart';
import '../../core/text/lyric_layout.dart';
import '../../core/text/lexicon.dart';
import '../../data/api_client.dart';
import '../../data/book_voice.dart';
import '../../data/habit.dart';
import '../../data/lexicon_loader.dart';
import '../../data/library.dart';
import '../../data/local_ai.dart';
import '../../data/notebook.dart';
import '../../data/segments.dart';
import '../../data/settings.dart';
import '../../data/sessions.dart';
import '../../data/settings_provider.dart';
import '../../services/mood.dart';
import '../../services/notifications.dart';
import '../../services/on_device_ai.dart';
import '../../services/scene_sound.dart';
import '../../services/read_aloud.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/typography.dart';
import '../../ui/vibes.dart';
import '../share/share_sheet.dart';
import 'cards/special_cards.dart';
import 'cards/text_card.dart';
import 'goal_setup_sheet.dart';
import 'mood_sheet.dart';
import 'page_mode.dart';
import 'session_complete.dart';
import 'word_sheet.dart';

/// Whether the reader's controls are showing (the tab bar follows them).
class ReaderChrome extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool visible) => state = visible;
}

final readerChromeProvider = NotifierProvider<ReaderChrome, bool>(ReaderChrome.new);

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.startSid, this.embedded = false});

  final String bookId;
  final String? startSid;

  /// Shown in the Reading tab (with the tab bar under the controls).
  final bool embedded;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
  PageController? _pager;
  List<FeedItem> _feed = const [];
  Object? _feedKey;
  Map<String, CardSentence> _sentences = const {};
  BookContent? _sentencesFor;
  int _page = 0;
  DateTime _shownAt = DateTime.now();
  bool _tts = false;
  int _textCardsThisSession = 0;

  /// Kept from initState: `ref` must not be used in dispose(), where the last
  /// card's reading time is still recorded.
  late final HabitNotifier _habit;
  late final MoodController _mood;
  late final SessionLog _sessions;

  /// The book's library entry as last built (title, progress), for the
  /// session log, which can still be written to while the reader closes.
  BookMeta? _meta;
  late final SceneSoundController _sound;
  late final ReadAloud _readAloud;
  Map<int, ChapterSegments>? _segments;
  final Set<int> _requestedAi = {};

  /// The chapter and block of cards the on-device model last wrote ahead for.
  (int, int)? _localBlock;

  /// Focus mode is off: the controls (top bar, rail, tab bar) are showing.
  /// A tap on empty space shows them; only the eye button hides them.
  bool _chrome = false;
  late final ReaderChrome _chromeFlag;

  void _setChrome(bool on) {
    if (_chrome == on) return;
    setState(() => _chrome = on);
    _chromeFlag.set(on);
  }

  /// The scene and on/off state the sound was last set for.
  (Vibe, bool)? _soundFor;

  /// "How are you feeling?" was checked for this opening of the book.
  bool _moodChecked = false;

  /// The mood Cloro picked the scene from, shown as "· change" for a moment.
  Mood? _moodChip;
  bool _moodChipShown = false;
  Timer? _moodChipTimer;

  /// Dwell on the earlier reels of a split card, by feed index (the card is
  /// credited once, on its last reel).
  final Map<int, int> _partDwell = {};
  bool _voiceChecked = false;

  /// A highlight is being adjusted with its handles.
  bool _selecting = false;

  /// A context under the reader's own theme: sheets and toasts opened from
  /// here wear the scene on screen (which can differ from the app's when the
  /// AI picks scenes).
  BuildContext? _themed;
  BuildContext get _ui => _themed != null && _themed!.mounted ? _themed! : context;

  @override
  void initState() {
    super.initState();
    _chromeFlag = ref.read(readerChromeProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _habit = ref.read(habitProvider.notifier);
    _mood = ref.read(moodProvider.notifier);
    _sessions = ref.read(sessionLogProvider.notifier);
    _sound = ref.read(sceneSoundProvider.notifier);
    _readAloud = ref.read(readAloudProvider);
  }

  /// Keeps the scene's ambient sound in step with the scene on screen
  /// (including the AI's Auto scenes) and the reader's on/off choice.
  void _syncSound(Vibe scene, bool on) {
    if (_soundFor == (scene, on)) return;
    _soundFor = (scene, on);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      on ? unawaited(_sound.play(scene)) : unawaited(_sound.stop());
      if (!_visible) unawaited(_sound.pause());
    });
  }

  /// The Reading tab is on screen (another tab hides it but keeps it alive).
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) {
      // Leaving the tab: no sound or voice in other tabs; count this reel.
      unawaited(_sound.pause());
      if (_tts) _toggleTts();
      _recordCurrent();
    } else {
      _shownAt = DateTime.now();
      unawaited(_sound.resume());
    }
  }

  /// The scene behind the card on screen: the AI's choice for this part of
  /// the chapter when Auto is on (paid tiers), otherwise the reader's vibe.
  Vibe _sceneFor(AppSettings s) {
    if (!s.autoScene || !s.tier.paid || s.vibe == Vibe.paper || _feed.isEmpty) return s.vibe;
    final item = _feed[_page.clamp(0, _feed.length - 1)];
    final name = _segments?[item.chapterIndex]?.sceneAt(item.cardIndexInChapter ?? 0);
    return Vibe.values.where((v) => v.name == name && v != Vibe.paper).firstOrNull ?? s.vibe;
  }

  /// Speaker button: mute the scene's sound (to play your own music), or
  /// bring it back.
  void _toggleSound(Vibe scene) {
    final on = !ref.read(settingsProvider).sceneSound;
    HapticFeedback.selectionClick();
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(sceneSound: on));
    showKitToast(
      _ui,
      on ? '${sceneSoundLabels[scene]}' : 'Scene sound off. Play your own music if you like.',
      icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void dispose() {
    // The tab bar shows again once the reader is gone.
    final flag = _chromeFlag;
    Future.microtask(() => flag.set(false));
    // Providers can't be modified while the tree is being torn down, so the
    // last card's reading time is recorded right after.
    _recordCurrent(deferred: true);
    scheduleMicrotask(_sound.stop);
    WidgetsBinding.instance.removeObserver(this);
    _moodChipTimer?.cancel();
    _pager?.dispose();
    unawaited(_readAloud.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // No scene sound while the app is in the background.
      unawaited(_sound.pause());
      _recordCurrent();
      final habit = ref.read(habitProvider);
      final notifier = ref.read(habitProvider.notifier);
      if (!habit.today(DateTime.now()).meets(ref.read(settingsProvider).goal)) {
        ReminderService.instance.scheduleStreakNudge(streak: notifier.displayStreak(), freezesLeft: notifier.freezesLeft());
      }
    } else if (state == AppLifecycleState.resumed && _visible) {
      _shownAt = DateTime.now();
      unawaited(_sound.resume());
      // Back after a while: maybe time to ask (or a new part of the day).
      if (_moodChecked) unawaited(_checkMood());
    }
  }

  // ---------------------------------------------------------------- feed

  void _ensureSentences(BookContent book) {
    if (identical(_sentencesFor, book)) return;
    final map = <String, CardSentence>{};
    for (final c in book.chapters) {
      for (final b in c.blocks) {
        for (var i = 0; i < b.sentences.length; i++) {
          map[b.sentences[i].id] = CardSentence(b.sentences[i], b, firstInBlock: i == 0);
        }
      }
    }
    _sentences = map;
    _sentencesFor = book;
  }

  void _ensureFeed(BookContent book, Map<int, ChapterSegments> segments, AppSettings s, BookMeta? meta) {
    // A reel holds only as much text as sits comfortably on this screen at
    // the reader's size; longer text continues on the next reel.
    final padding = MediaQuery.paddingOf(context);
    final maxReelWords = reelWordBudget(
      screen: MediaQuery.sizeOf(context),
      topInset: padding.top,
      bottomInset: padding.bottom,
      fontSize: s.fontSize,
      length: s.cardLength,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    final key = (segments, s.recallCards, s.reflectCards, maxReelWords);
    if (_feedKey == key) return;
    // Where the reader is: an explicit start, the saved position, or (when
    // the feed is rebuilt) the reel on screen.
    final (String? anchor, int anchorOffset) = _feed.isNotEmpty
        ? _currentAnchor()
        : widget.startSid != null
            ? (widget.startSid, 0)
            : (meta?.positionSid, meta?.positionOffset ?? 0);
    _feed = buildFeed(
      book,
      segments,
      FeedOptions(
        recallCards: s.recallCards,
        reflectCards: s.reflectCards,
        // Short cards: a quick check every ~15 cards instead of ~10.
        recallEvery: s.cardLength == CardLength.snack ? 15 : 10,
        maxReelWords: maxReelWords,
      ),
    );
    _feedKey = key;
    _partDwell.clear();
    var index = feedIndexForSid(_feed, anchor, offset: anchorOffset);
    // A book opened for the first time starts at its own text (the
    // introduction or first chapter), past the title page and copyright.
    if (anchor == null) index = math.max(0, _feed.indexWhere((f) => f.chapterIndex >= book.bodyStart));
    _page = index;
    if (_pager == null) {
      _pager = PageController(initialPage: index);
    } else if (_pager!.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pager!.hasClients) _pager!.jumpToPage(index);
      });
    }
    _shownAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRequestAi(book));
  }

  (String?, int) _currentAnchor() {
    for (var i = _page; i >= 0 && i < _feed.length; i--) {
      final sid = _feed[i].anchorSid;
      if (sid != null) return (sid, _feed[i].offset ?? 0);
    }
    return (null, 0);
  }

  /// Cards between recaps and quick checks.
  int get _blockSize => ref.read(settingsProvider).cardLength == CardLength.snack ? 15 : 10;

  /// Free with the on-device model: writes the next recaps, quick checks and
  /// the chapter teaser just ahead of the reader, a block at a time.
  void _maybeRequestLocal(BookContent book) {
    if (_feed.isEmpty || !ref.read(onDeviceAiProvider.notifier).usable) return;
    // The text card on screen, or the last one before it.
    FeedItem? item;
    for (var i = _page.clamp(0, _feed.length - 1); i >= 0; i--) {
      if (_feed[i].cardIndexInChapter != null) {
        item = _feed[i];
        break;
      }
    }
    final ch = item?.chapterIndex ?? _feed[_page.clamp(0, _feed.length - 1)].chapterIndex;
    final fromCard = item?.cardIndexInChapter ?? 0;
    final seg = _segments?[ch];
    if (seg == null) return;
    final block = (ch, fromCard ~/ _blockSize);
    if (block == _localBlock) return;
    _localBlock = block;
    final length = ref.read(settingsProvider).cardLength;
    final writer = ref.read(localAiSegmenterProvider);
    void reload(bool changed) {
      if (!changed || !mounted) return;
      _localBlock = null; // look again from wherever the reader is now
      ref.invalidate(segmentsProvider((bookId: widget.bookId, length: length)));
    }

    writer.ensure(bookId: widget.bookId, book: book, seg: seg, fromCard: fromCard, length: length, every: _blockSize).then(reload);
    // In a chapter's last block, get the next chapter's teaser and first recap ready.
    final next = _segments?[ch + 1];
    if (next != null && fromCard >= seg.cards.length - _blockSize) {
      writer.ensure(bookId: widget.bookId, book: book, seg: next, fromCard: 0, length: length, every: _blockSize).then(reload);
    }
  }

  void _maybeRequestAi(BookContent book) async {
    _maybeRequestLocal(book);
    if (_feed.isEmpty) return;
    final ch = _feed[_page.clamp(0, _feed.length - 1)].chapterIndex;
    final wanted = [ch, ch + 1].where((c) => c < book.chapters.length && !_requestedAi.contains(c)).toList();
    if (wanted.isEmpty) return;
    _requestedAi.addAll(wanted);
    final changed = await ref.read(aiSegmenterProvider).ensureChapters(widget.bookId, book, wanted);
    if (changed && mounted) {
      ref.invalidate(segmentsProvider((bookId: widget.bookId, length: ref.read(settingsProvider).cardLength)));
    }
  }

  // ---------------------------------------------------------------- tracking

  int _wordsOf(FeedItem item) => item.words ?? item.card!.wordCount;

  /// The exact text on a reel (a reel may show only some lines of its sentences).
  String _reelText(FeedItem item) {
    final lines = item.lines;
    if (lines == null) return item.shownSids.map((sid) => _sentences[sid]?.sentence.text ?? '').join(' ');
    final pieces = piecesForCard(item.card!, [
      for (final sid in item.layoutSids)
        if (_sentences[sid] != null)
          (sid: sid, text: _sentences[sid]!.sentence.text, block: _sentences[sid]!.block.index, type: _sentences[sid]!.block.type),
    ]);
    return pieces.sublist(lines.from.clamp(0, pieces.length), lines.to.clamp(0, pieces.length)).map((p) => p.text).join(' ');
  }

  /// Records dwell time for the card currently on screen. A card shown as
  /// several reels (text · spotlight · text) counts once, when its last reel
  /// is left, for the reels read in this session.
  CardRecord? _recordCurrent({bool deferred = false}) {
    if (_feed.isEmpty || _page >= _feed.length) return null;
    final item = _feed[_page];
    final dwell = DateTime.now().difference(_shownAt).inMilliseconds;
    _shownAt = DateTime.now();
    if (item.kind != CardKind.text || item.card == null) return null;
    final card = item.card!;
    if (!item.lastPart) {
      _partDwell[_page] = (_partDwell[_page] ?? 0) + dwell;
      return null;
    }
    var total = dwell;
    var words = _wordsOf(item);
    for (var i = _page - 1; i >= 0 && identical(_feed[i].card, card); i--) {
      final earlier = _partDwell.remove(i);
      if (earlier == null) continue; // not read in this session
      total += earlier;
      words += _wordsOf(_feed[i]);
    }
    if (total < 300) return null;
    CardRecord record() {
      _mood.addMinutes(total);
      final meta = _meta;
      if (meta != null) {
        _sessions.record(
          bookId: widget.bookId,
          title: meta.title,
          author: meta.author,
          dwellMs: total,
          progress: meta.progress,
          mood: _mood.recent?.name,
        );
      }
      return _habit.recordCard(
        words: words,
        dwellMs: total,
        bookId: widget.bookId,
        cardRef: '${widget.bookId.substring(0, 12)}:${card.startSid}',
      );
    }
    if (deferred) {
      scheduleMicrotask(record);
      return null;
    }
    return record();
  }

  void _onPageChanged(int index, BookContent book, BookMeta? meta) {
    final record = _recordCurrent();
    _page = index;
    _shownAt = DateTime.now();
    HapticFeedback.selectionClick();
    final item = _feed[index];
    final settings = ref.read(settingsProvider);

    if (item.kind == CardKind.text && item.card != null) {
      final anchor = item.anchorSid ?? item.card!.startSid;
      ref.read(libraryProvider.notifier).updatePosition(
            widget.bookId,
            sid: anchor,
            offset: item.offset ?? 0,
            progress: progressAt(book, anchor),
          );
      _textCardsThisSession++;
      if (!settings.goalSetupDone && _textCardsThisSession == 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showGoalSetup(_ui);
        });
      }
      if (_tts) _speak(item);
    }
    _maybeRequestLocal(book);
    if (item.kind == CardKind.milestone) {
      if (ref.read(libraryProvider.notifier).markFinished(widget.bookId)) {
        ref.read(habitProvider.notifier).bookFinished();
        final api = ref.read(apiProvider);
        if (api.enabled) unawaited(api.bookFinished(book.title).catchError((_) {}));
      }
    }
    if (_feed[index].chapterIndex != (index > 0 ? _feed[index - 1].chapterIndex : -1)) _maybeRequestAi(book);
    if (record != null && record.goalJustMet) {
      ReminderService.instance.cancelStreakNudge();
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSessionComplete(record, book, meta));
    }
    setState(() {});
  }

  Future<void> _showSessionComplete(CardRecord record, BookContent book, BookMeta? meta) async {
    if (!mounted) return;
    final today = ref.read(habitProvider).today(DateTime.now());
    final idea = _ideaOfTheDay();
    final choice = await showSessionComplete(
      _ui,
      cards: today.verifiedCards,
      minutes: today.minutes,
      streak: record.streak,
      milestone: record.milestone,
      ideaOfTheDay: idea,
      ideaSource: idea == null ? null : '${book.author}, ${book.title}',
    );
    if (!mounted) return;
    switch (choice) {
      case SessionChoice.share:
        await showShareSheet(
          _ui,
          ProgressShare(
            emoji: '🔥',
            headline: '${record.streak}-day reading streak',
            lines: ['${today.verifiedCards} cards today · ${today.minutes.round()} min', 'Reading ${book.title}'],
          ),
        );
      case SessionChoice.done:
        context.go('/today');
      case SessionChoice.keepReading:
      case null:
        break;
    }
  }

  String? _ideaOfTheDay() {
    final notebook = ref.read(notebookProvider);
    final today = dateKey(DateTime.now());
    final h = notebook.highlights
        .where((h) => h.bookId == widget.bookId && dateKey(h.createdAt) == today)
        .firstOrNull;
    if (h != null) return h.text;
    for (var i = _page; i >= 0 && i > _page - 12; i--) {
      final card = _feed[i].card;
      if (card != null && card.keySids.isNotEmpty) return _sentences[card.keySids.first]?.sentence.text;
    }
    return null;
  }

  /// The text of the next reel that has words, to fetch its audio early.
  String? _nextReelText(int from) {
    for (var i = from + 1; i < _feed.length && i <= from + 3; i++) {
      if (_feed[i].kind == CardKind.text && _feed[i].card != null) return _reelText(_feed[i]);
    }
    return null;
  }

  void _speak(FeedItem item) {
    final text = _reelText(item);
    _sound.duck(true);
    _readAloud.speak(text, next: _nextReelText(_page), onDone: () {
      _sound.duck(false);
      if (mounted && _tts && _pager != null && _page < _feed.length - 1) {
        _pager!.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ---------------------------------------------------------------- actions

  void _share(BookContent book, BookMeta? meta, FeedItem item) {
    final card = item.card;
    if (card == null) return;
    final notebook = ref.read(notebookProvider);
    final shown = item.shownSids;
    final highlighted = [
      for (final sid in shown)
        if (notebook.highlightFor(widget.bookId, sid) != null || card.keySids.contains(sid)) _sentences[sid]!.sentence.text,
    ];
    showShareSheet(
      _ui,
      QuoteShare(
        // A spotlight reel shares its line; other reels their highlights or text.
        sentences: item.spotlight
            ? [for (final sid in shown) _sentences[sid]?.sentence.text ?? '']
            : highlighted.isNotEmpty
                ? highlighted
                : [for (final sid in shown) _sentences[sid]?.sentence.text ?? ''],
        bookTitle: book.title,
        author: book.author,
        publicDomain: meta?.isPublicDomain ?? false,
        chapter: book.chapters[card.chapterIndex].title,
      ),
    );
  }

  void _toggleSave(BookContent book, FeedItem item) {
    final card = item.card;
    if (card == null) return;
    final notebook = ref.read(notebookProvider.notifier);
    final saved = notebook.toggleSaved(SavedCard(
      id: notebook.newId(),
      bookId: widget.bookId,
      bookTitle: book.title,
      author: book.author,
      chapterTitle: book.chapters[card.chapterIndex].title,
      startSid: item.anchorSid!,
      text: [for (final sid in item.shownSids) _sentences[sid]?.sentence.text ?? ''].join(' '),
      createdAt: DateTime.now(),
    ));
    HapticFeedback.lightImpact();
    // A saved line from a public-domain book goes on the session's card.
    if (saved && (_meta?.isPublicDomain ?? false)) {
      _sessions.quote(widget.bookId, [for (final sid in item.shownSids) _sentences[sid]?.sentence.text ?? ''].join(' '));
    }
    showKitToast(
      _ui,
      saved ? 'Saved to your Notebook 🔖' : 'Removed from saved',
      icon: saved ? Icons.bookmark_rounded : Icons.bookmark_remove_rounded,
      duration: const Duration(milliseconds: 1600),
    );
  }

  /// A highlight's range is being adjusted: the page holds still.
  void _setSelecting(bool on) {
    if (_selecting != on && mounted) setState(() => _selecting = on);
  }

  void _toggleTts() {
    setState(() => _tts = !_tts);
    if (_tts && _feed[_page].card != null) {
      _speak(_feed[_page]);
    } else {
      unawaited(_readAloud.stop());
      _sound.duck(false);
    }
  }

  Future<void> _editNote(Highlight h) async {
    if (!mounted) return;
    final note = await showKitPrompt(_ui, title: 'Note', message: h.text, hint: 'Your thoughts…', initial: h.note ?? '', maxLines: 4);
    if (note != null) ref.read(notebookProvider.notifier).updateHighlight(h.copyWith(note: note));
  }

  Future<void> _openContents(BookContent book) async {
    final current = _feed.isNotEmpty ? _feed[_page].chapterIndex : -1;
    final wpm = ref.read(habitProvider).wpm;
    final chapter = await showKitSheet<int>(
      _ui,
      title: 'Contents',
      subtitle: book.title,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (final c in book.chapters)
          KitRow(
            title: c.title,
            subtitle: c.index < book.bodyStart ? 'Front matter' : '~${(c.wordCount / wpm).ceil()} min',
            selected: c.index == current,
            chevron: false,
            onTap: () => Navigator.of(context).pop(c.index),
          ),
      ]),
    );
    if (chapter == null) return;
    final index = _feed.indexWhere((f) => f.kind == CardKind.chapterTitle && f.chapterIndex == chapter);
    if (index >= 0) _pager?.jumpToPage(index);
  }

  Future<void> _openPageMode(BookContent book, AppSettings s, ReadingTheme theme) async {
    _recordCurrent();
    final item = _feed[_page];
    final sid = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PageModeView(
        book: book,
        chapterIndex: item.chapterIndex,
        anchorSid: _currentAnchor().$1,
        settings: s,
        theme: theme,
      ),
    ));
    _shownAt = DateTime.now();
    if (sid != null && mounted) _pager?.jumpToPage(feedIndexForSid(_feed, sid));
  }

  /// Everything else, in one sheet (long press on empty space, or the rail's
  /// last button): theme, scene sound, contents, page mode, goal, gestures,
  /// settings, and "this cut feels wrong".
  Future<void> _options(BookContent book, AppSettings s, ReadingTheme theme) async {
    final choice = await showKitSheet<String>(
      _ui,
      title: book.title,
      subtitle: book.author,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(settingsProvider);
        final scene = _sceneFor(s);
        final style = vibeStyles[scene]!;
        final auto = s.autoScene && s.tier.paid && s.vibe != Vibe.paper;
        void pick(String v) => Navigator.of(context).pop(v);
        final mood = ref.watch(moodProvider).current;
        final moodOn = ref.read(moodProvider.notifier).active;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          KitGroup(children: [
            KitRow(emoji: auto ? '✨' : style.emoji, title: 'Theme', value: auto ? 'Auto' : style.label, onTap: () => pick('theme')),
            if (moodOn)
              KitRow(emoji: mood?.emoji ?? '🙂', title: 'Mood', value: mood?.label ?? 'Not set', onTap: () => pick('mood')),
            KitSwitchRow(
              icon: s.sceneSound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              title: 'Scene sound',
              subtitle: sceneSoundLabels[scene],
              value: s.sceneSound,
              onChanged: (_) => _toggleSound(scene),
            ),
            KitRow(icon: Icons.format_list_bulleted_rounded, title: 'Contents', onTap: () => pick('toc')),
            KitRow(icon: Icons.chrome_reader_mode_rounded, title: 'Page mode', subtitle: 'Read the chapter as one page', onTap: () => pick('page')),
            KitRow(icon: Icons.flag_rounded, title: 'Daily goal', onTap: () => pick('goal')),
            KitRow(icon: Icons.touch_app_rounded, title: 'Gestures', onTap: () => pick('gestures')),
            KitRow(icon: Icons.settings_rounded, title: 'Settings', onTap: () => pick('settings')),
          ]),
          KitGroup(divided: true, children: [
            KitRow(icon: Icons.content_cut_rounded, title: 'This cut feels wrong', chevron: false, onTap: () => pick('report')),
          ]),
        ]);
      }),
    );
    if (!mounted) return;
    switch (choice) {
      case 'theme':
        _pickVibe();
      case 'mood':
        _askMood(correcting: ref.read(moodProvider).current != null);
      case 'toc':
        _openContents(book);
      case 'page':
        _openPageMode(book, s, theme);
      case 'goal':
        showGoalSheet(_ui);
      case 'gestures':
        ref.read(settingsProvider.notifier).update((x) => x.copyWith(gestureTutorialSeen: false));
      case 'settings':
        context.push('/settings');
      case 'report':
        showKitToast(_ui, 'Thanks! Reports like this help us cut cards better.', emoji: '✂️');
    }
  }

  /// On opening the book (and coming back to it): ask how you feel while
  /// Cloro is learning, or use the mood it predicted for this part of the day.
  Future<void> _checkMood() async {
    if (!mounted || !_mood.active) return;
    if (_mood.shouldAsk()) return _askMood();
    await _mood.refreshPrediction();
    if (!mounted) return;
    final picked = _mood.applyPrediction();
    if (picked != null) _showMoodChip(picked);
  }

  Future<void> _askMood({bool correcting = false}) async {
    final picked = await showMoodSheet(_ui, current: ref.read(moodProvider).current);
    if (!mounted) return;
    if (picked == null) {
      if (!correcting) _mood.skip();
      return;
    }
    HapticFeedback.selectionClick();
    _mood.answer(picked, corrected: correcting);
    setState(() => _moodChipShown = false);
  }

  void _showMoodChip(Mood mood) {
    _moodChipTimer?.cancel();
    setState(() {
      _moodChip = mood;
      _moodChipShown = true;
    });
    _moodChipTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _moodChipShown = false);
    });
  }

  /// The note box: an empty page for your own thoughts on this reel, kept in
  /// the Notebook with the passage it was written on.
  Future<void> _writeThought(BookContent book, FeedItem item) async {
    final text = await showKitPrompt(_ui, title: 'Your thoughts', hint: 'What does this make you think?', maxLines: 6);
    if (text == null || text.trim().isEmpty || !mounted) return;
    ref.read(notebookProvider.notifier).addReflection(
          bookTitle: book.title,
          chapterTitle: book.chapters[item.chapterIndex].title,
          text: text,
          quote: _reelText(item),
        );
    showKitToast(_ui, 'Saved to your Notebook', emoji: '📝');
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final paperTheme = ReadingTheme.of(effectiveReadingTheme(settings, MediaQuery.platformBrightnessOf(context)));
    _segments = ref.watch(segmentsProvider((bookId: widget.bookId, length: settings.cardLength))).value ?? _segments;
    final scene = _sceneFor(settings);
    final readingTheme = readingThemeForVibe(scene, paperTheme);
    final meta = ref.watch(libraryProvider).where((b) => b.id == widget.bookId).firstOrNull;
    _meta = meta;
    final contentAsync = ref.watch(bookContentProvider(widget.bookId));
    final segmentsAsync = ref.watch(segmentsProvider((bookId: widget.bookId, length: settings.cardLength)));
    final lexicon = ref.watch(lexiconProvider).value ?? Lexicon.empty;

    Widget body;
    final error = contentAsync.error ?? segmentsAsync.error;
    if (error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open this book.\n$error', style: TextStyle(color: readingTheme.text))));
    } else if (contentAsync.value == null || segmentsAsync.value == null) {
      body = const Center(child: KitSpinner());
    } else {
      final book = contentAsync.value!;
      _ensureSentences(book);
      _ensureFeed(book, segmentsAsync.value!, settings, meta);
      if (!_voiceChecked) {
        _voiceChecked = true;
        // The book's fonts: on-device guess now, the AI's choice on paid tiers.
        WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(bookVoiceProvider).ensure(widget.bookId, book));
      }
      final type = BookType(voiceByName(meta?.voice), settings);
      body = _buildReader(book, meta, settings, readingTheme, type, lexicon);
    }

    // The reader wears the scene on screen (Auto scenes included): its sheets,
    // menus and controls take the scene's colours, whatever the app's
    // light or dark theme is.
    final theme = cachedAppTheme(
      ('reader', scene, paperTheme, settings.animatedBackground),
      () => Kit.forScene(scene, paperTheme, motion: settings.animatedBackground),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readingTheme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(
        data: theme,
        child: Builder(builder: (context) {
          _themed = context;
          return _scaffold(scene, settings, paperTheme, readingTheme, body);
        }),
      ),
    );
  }

  Widget _scaffold(Vibe scene, AppSettings settings, ReadingTheme paperTheme, ReadingTheme readingTheme, Widget body) {
    return Scaffold(
        backgroundColor: paperTheme.background,
        body: Stack(children: [
          // AI-picked (or chosen) scene; crossfades when the story moves.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1400),
              child: Stack(key: ValueKey(scene), fit: StackFit.expand, children: [
                // Still while reels scroll: only its own slow motion repaints it.
                VibeBackground(
                  vibe: scene,
                  animate: settings.animatedBackground,
                  paperColor: paperTheme.background,
                ),
                // The scene's calibrated shade: stays put while reels move.
                if (readingTheme.scrim != null)
                  IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: readingTheme.scrim))),
              ]),
            ),
          ),
          Positioned.fill(child: body),
        ]),
    );
  }

  Widget _buildReader(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, BookType type, Lexicon lexicon) {
    final notebook = ref.watch(notebookProvider);
    final habit = ref.watch(habitProvider);
    final today = habit.today(DateTime.now());
    final goal = s.goal;
    final padding = MediaQuery.paddingOf(context);
    final scene = _sceneFor(s);
    final chromeColor = t.text;
    _syncSound(scene, s.sceneSound);
    if (widget.embedded && !_moodChecked && s.gestureTutorialSeen && _feed.isNotEmpty) {
      _moodChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkMood()));
    }

    return Stack(children: [
      PageView.builder(
        controller: _pager,
        scrollDirection: Axis.vertical,
        physics: _selecting ? const NeverScrollableScrollPhysics() : const _ReelPagePhysics(),
        itemCount: _feed.length,
        onPageChanged: (i) => _onPageChanged(i, book, meta),
        itemBuilder: (context, i) => _buildItem(book, meta, s, t, type, lexicon, notebook, _feed[i], i == _page, padding),
      ),
      // Today's goal as one thin line that fills as you read: always there, never in the way.
      Positioned(
        top: padding.top + 6,
        left: 16,
        right: 16,
        child: _GoalLine(progress: today.progress(goal), color: chromeColor, track: chromeColor.withValues(alpha: 0.22)),
      ),
      // With the controls: the focus (eye) button and where you are.
      Positioned(
        top: padding.top + 14,
        left: 4,
        right: 4,
        child: FadeChrome(
          visible: _chrome,
          child: _TopBar(
            color: chromeColor,
            shadows: t.textShadows,
            title: _feed.isEmpty ? book.title : book.chapters[_feed[_page.clamp(0, _feed.length - 1)].chapterIndex].title,
            onFocus: () => _setChrome(false),
          ),
        ),
      ),
      // "😌 Calm · change" when the scene was picked from your mood.
      Positioned(
        top: padding.top + 58,
        left: 0,
        right: 0,
        child: Center(
          child: MoodChip(
            mood: _moodChip,
            visible: _moodChipShown,
            theme: t,
            onTap: () => _askMood(correcting: true),
          ),
        ),
      ),
      if (!s.gestureTutorialSeen && _feed.isNotEmpty)
        Positioned.fill(
          child: _GestureGuide(
            onDone: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(gestureTutorialSeen: true)),
          ),
        ),
    ]);
  }

  Future<void> _pickVibe() async {
    final s = ref.read(settingsProvider);
    final paid = s.tier.paid;
    // null = Auto (the AI picks the scene for each part of the book).
    final picked = await showKitSheet<(Vibe?,)>(
      _ui,
      title: 'Pick your vibe',
      subtitle: paid ? 'Auto lets the AI choose the scene that fits each chapter.' : 'Auto (AI-picked scenes) comes with every paid plan.',
      builder: (context) => VibePickerRow(
        selected: s.vibe,
        autoSelected: paid && s.autoScene && s.vibe != Vibe.paper,
        onAuto: paid ? () => Navigator.of(context).pop((null,)) : null,
        onSelected: (v) => Navigator.of(context).pop((v,)),
      ),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    final vibe = picked.$1;
    ref.read(settingsProvider.notifier).update((x) => vibe == null ? x.copyWith(autoScene: true) : x.copyWith(vibe: vibe, autoScene: false));
  }

  Widget _buildItem(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, BookType type, Lexicon lexicon,
      NotebookState notebook, FeedItem item, bool active, EdgeInsets padding) {
    final card = _card(book, meta, s, t, type, lexicon, notebook, item, active, padding);
    if (item.kind == CardKind.text) return card;
    // Chapter, recap, quiz and other cards: the same empty-space gestures.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _setChrome(true),
      onLongPress: () => _options(book, s, t),
      child: card,
    );
  }

  Widget _card(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, BookType type, Lexicon lexicon,
      NotebookState notebook, FeedItem item, bool active, EdgeInsets padding) {
    final today = ref.read(habitProvider).today(DateTime.now());
    switch (item.kind) {
      case CardKind.text:
        final card = item.card!;
        return PostCard(
          key: ValueKey('${item.anchorSid}-${item.lines?.from}-${item.spotlight}-${s.cardLength.name}'),
          card: card,
          sentences: [for (final sid in item.layoutSids) if (_sentences[sid] != null) _sentences[sid]!],
          lines: item.lines,
          spotlight: item.spotlight,
          type: type,
          bookTitle: book.title,
          chapterTitle: book.chapters[card.chapterIndex].title,
          position: '${(item.cardIndexInChapter ?? 0) + 1} / ${item.cardsInChapter ?? 0}',
          coverPath: meta?.coverPath,
          settings: s,
          theme: t,
          lexicon: lexicon,
          active: active,
          // Likes and saves belong to the reel on screen (the card, or one part of it).
          liked: notebook.liked.contains('${widget.bookId}|${item.anchorSid}'),
          saved: notebook.isSaved(widget.bookId, item.anchorSid!),
          listening: _tts,
          highlightsIn: (sid) => notebook.highlightsIn(widget.bookId, sid),
          onCreateHighlight: (sentence) => ref
              .read(notebookProvider.notifier)
              .addHighlight(bookId: widget.bookId, bookTitle: book.title, sid: sentence.id, text: sentence.text),
          onSaveHighlight: (h, absorbed) {
            ref.read(notebookProvider.notifier).saveHighlight(h, absorbed: absorbed);
            if (_meta?.isPublicDomain ?? false) _sessions.quote(widget.bookId, h.text);
          },
          onRemoveHighlight: (id) => ref.read(notebookProvider.notifier).removeHighlight(id),
          onNoteHighlight: _editNote,
          onSelecting: _setSelecting,
          chrome: _chrome,
          streak: ref.read(habitProvider.notifier).displayStreak(),
          goalLabel: s.goal.unit == GoalUnit.cards
              ? '${today.verifiedCards}/${s.goal.dailyTarget}'
              : '${today.minutes.floor()}/${s.goal.dailyTarget}m',
          goalDone: today.meets(s.goal),
          onStreak: () => showStreakSheet(_ui),
          onGoal: () => showGoalSheet(_ui),
          onOptions: () => _options(book, s, t),
          onTapEmpty: () => _setChrome(true),
          // In the Reading tab the tab bar shows with the controls: keep the rail above it.
          railLift: widget.embedded && _chrome ? KitNavBar.reservedHeight - 10 : 0,
          onLongPressEmpty: () => _options(book, s, t),
          onTapWord: (word, sentence) {
            final meaning = card.hardWords
                .where((h) => h.word.toLowerCase() == word.toLowerCase() && h.meaning != null)
                .map((h) => h.meaning)
                .firstOrNull;
            final local = ref.read(onDeviceAiProvider.notifier);
            showWordSheet(_ui,
                word: word,
                sentence: sentence.text,
                bookTitle: book.title,
                lexicon: lexicon,
                contextMeaning: meaning,
                // Free with the on-device model: asked now, ahead of background work.
                onDeviceMeaning: local.usable
                    ? () => local.run<String?>(
                          (llm) => const LocalWriter().meaning(llm, word: word, sentence: sentence.text),
                          urgent: true,
                        )
                    : null);
          },
          onLike: () => ref.read(notebookProvider.notifier).toggleLike(widget.bookId, item.anchorSid!),
          onSave: () => _toggleSave(book, item),
          onShare: () => _share(book, meta, item),
          onNote: () => _writeThought(book, item),
          onListen: _toggleTts,
          onOverscroll: (dir) {
            if (dir > 0) {
              _pager?.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
            } else {
              _pager?.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
            }
          },
        );
      case CardKind.chapterTitle:
        final c = book.chapters[item.chapterIndex];
        return ChapterTitleCardView(
          title: c.title,
          chapterNumber: item.chapterIndex + 1,
          cards: item.cardsInChapter ?? 0,
          minutes: (c.wordCount / ref.read(habitProvider).wpm).ceil(),
          teaser: item.teaser,
          settings: s,
          theme: t,
          type: type,
        );
      case CardKind.recap:
        return RecapCardView(bullets: item.recapBullets!, settings: s, theme: t, type: type);
      case CardKind.recall:
        return RecallCardView(
          settings: s,
          theme: t,
          type: type,
          question: item.recall,
          revealSentences: [for (final sid in item.recallSids ?? const <String>[]) _sentences[sid]?.sentence.text ?? ''],
          onAnswered: (_) => HapticFeedback.selectionClick(),
        );
      case CardKind.reflect:
        return ReflectCardView(
          settings: s,
          theme: t,
          type: type,
          onSave: (text) => ref.read(notebookProvider.notifier).addReflection(
                bookTitle: book.title,
                chapterTitle: book.chapters[item.chapterIndex].title,
                text: text,
              ),
        );
      case CardKind.milestone:
        return MilestoneCardView(
          bookTitle: book.title,
          settings: s,
          theme: t,
          type: type,
          onShare: () => showShareSheet(
            _ui,
            ProgressShare(
              emoji: '🎉',
              headline: 'Finished ${book.title}',
              lines: ['by ${book.author}', '${_feed.where((f) => f.kind == CardKind.text).length} reels'],
            ),
          ),
          onDone: () => context.go('/library'),
        );
    }
  }
}

/// Page physics with slight resistance so swipes feel deliberate.
class _ReelPagePhysics extends PageScrollPhysics {
  const _ReelPagePhysics({super.parent});

  @override
  _ReelPagePhysics applyTo(ScrollPhysics? ancestor) => _ReelPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => const SpringDescription(mass: 1, stiffness: 140, damping: 22);

  @override
  double get dragStartDistanceMotionThreshold => 6;
}

/// Today's goal as one continuous line that fills as you read.
class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.progress, required this.color, required this.track});

  final double progress;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Today\'s goal ${(progress * 100).round()} percent',
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => KitProgress(value: v, height: 2.5, color: color, track: track),
        ),
      );
}

/// With the controls showing: the focus (eye) button, which hides them all
/// again, and the chapter you're in. (No close button: switch tabs to leave.)
class _TopBar extends StatelessWidget {
  const _TopBar({required this.color, required this.shadows, required this.title, required this.onFocus});

  final Color color;
  final List<Shadow>? shadows;
  final String title;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) => Row(children: [
        KitIconButton(
          icon: Icons.visibility_outlined,
          semanticLabel: 'Focus: hide the controls',
          onPressed: onFocus,
          glass: false,
          color: color,
          shadows: shadows,
          iconSize: 25,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15, shadows: shadows)),
        ),
      ]);
}

/// One-time overlay that teaches the gestures (can be reopened from ⋯).
class _GestureGuide extends StatelessWidget {
  const _GestureGuide({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    const rows = [
      (Icons.swipe_up_outlined, 'Swipe up', 'Next reel'),
      (Icons.translate, 'Tap a word', 'Its meaning'),
      (Icons.touch_app_outlined, 'Tap empty space', 'Show the buttons (the eye hides them)'),
      (Icons.border_color_rounded, 'Long-press a word', 'Highlight it, then drag the handles'),
      (Icons.more_horiz_rounded, 'Long-press empty space', 'Theme, sound, contents and more'),
      (Icons.favorite, 'Double-tap', 'Like'),
      (Icons.swipe_left_outlined, 'Swipe left', 'Save'),
      (Icons.swipe_right_outlined, 'Swipe right', 'Share'),
    ];
    return GestureDetector(
      onTap: onDone,
      child: Container(
        color: const Color(0xCC0B0F14),
        padding: const EdgeInsets.all(32),
        child: SafeArea(
          // Scrolls on short screens (landscape, large text).
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Read like you scroll',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  KitBubble(icon: r.$1, color: Colors.white, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${r.$2}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: r.$3, style: const TextStyle(color: Colors.white70)),
                    ]), style: const TextStyle(color: Colors.white, fontSize: 17)),
                  ),
                ]),
              ),
            const SizedBox(height: 28),
            KitButton(label: 'Got it', onPressed: onDone),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

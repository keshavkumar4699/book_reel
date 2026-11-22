import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
import '../../services/notifications.dart';
import '../../services/on_device_ai.dart';
import '../../services/music.dart';
import '../../services/read_aloud.dart';
import '../../ui/backdrops.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/typography.dart';
import '../../ui/vibes.dart';
import '../share/progress_shares.dart';
import '../share/share_sheet.dart';
import 'cards/special_cards.dart';
import 'cards/text_card.dart';
import 'goal_setup_sheet.dart';
import 'page_mode.dart';
import 'session_complete.dart';
import 'word_sheet.dart';

/// Whether the reader's controls are showing (the tab bar follows them).
class ReaderChrome extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool visible) {
    // Called just after a reader is torn down, when the app may be closing too.
    if (ref.mounted) state = visible;
  }
}

final readerChromeProvider = NotifierProvider<ReaderChrome, bool>(ReaderChrome.new);

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.startSid, this.embedded = false});

  final String bookId;
  final String? startSid;

  /// Shown in the Reading tab (with the tab bar under the controls).
  final bool embedded;

  /// The time on each reel is measured with this clock (tests move it on).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
  PageController? _pager;

  /// Bumped when the pager is replaced: the page view starts afresh on it.
  int _pagerGeneration = 0;
  List<FeedItem> _feed = const [];
  Object? _feedKey;
  final FeedCache _feedCache = FeedCache();

  /// A swipe is under way (from the first move until the page comes to rest).
  bool _scrolling = false;

  /// The feed changed during a swipe: it's rebuilt once the page rests.
  bool _feedStale = false;

  /// Reading time of cards left during the swipe, credited when the page
  /// rests, so no frame of a swipe waits on storage or a rebuild.
  final List<({int words, int dwellMs, String cardRef})> _credits = [];

  /// The reel read aloud last, so a page coming to rest doesn't repeat it.
  FeedItem? _spoken;

  /// The reel that was on screen when the feed was rebuilt under it: it
  /// shows at once on the new page view instead of fading in again.
  FeedItem? _steady;

  /// The place last saved for this book.
  (String, int)? _savedAt;
  bool _goalSetupAsked = false;
  Map<String, CardSentence> _sentences = const {};
  BookContent? _sentencesFor;
  int _page = 0;
  DateTime _shownAt = ReaderScreen.clock();
  bool _tts = false;

  /// The reel being read aloud is still being turned into audio.
  bool _preparing = false;

  void _onWaiting() {
    final preparing = _readAloud.waiting.value != null;
    if (preparing != _preparing && mounted) setState(() => _preparing = preparing);
  }
  int _textCardsThisSession = 0;

  /// Kept from initState: `ref` must not be used in dispose(), where the last
  /// card's reading time is still recorded.
  late final HabitNotifier _habit;
  late final SessionLog _sessions;
  late final LibraryNotifier _library;

  /// The book's library entry as last built (title, progress), for the
  /// session log, which can still be written to while the reader closes.
  BookMeta? _meta;
  late final MusicPlayer _music;

  /// The picture (or scene) behind the reels: a random one when the book
  /// opens, changed from the strip at the top.
  Backdrop? _backdrop;
  bool _looksWarmed = false;
  late final ReadAloud _readAloud;
  Map<int, ChapterSegments>? _segments;
  final Set<int> _requestedAi = {};

  /// The chapter and block of cards the on-device model last wrote ahead for.
  (int, int)? _localBlock;

  /// The controls that come and go (the top bar and pictures, the music at
  /// the bottom, the tab bar) are showing; the rail of actions always is. A
  /// tap on empty space shows them, or hides them again; they hide on their
  /// own six seconds after the last touch, so the reel is left alone.
  bool _chrome = false;
  late final ReaderChrome _chromeFlag;
  Timer? _chromeTimer;
  static const chromeFor = Duration(seconds: 6);

  void _setChrome(bool on) {
    _chromeTimer?.cancel();
    // With TalkBack and the like, controls stay until hidden: finding a
    // button by touch takes longer than a few seconds.
    if (on && !(MediaQuery.maybeAccessibleNavigationOf(context) ?? false)) {
      _chromeTimer = Timer(chromeFor, () {
        if (mounted) _setChrome(false);
      });
    }
    if (_chrome == on) return;
    setState(() => _chrome = on);
    _chromeFlag.set(on);
    if (on) _warmLooks();
  }

  /// Dwell on the earlier reels of a split card (the card is credited once,
  /// on its last reel). By reel, which survives the feed being rebuilt.
  final Map<FeedItem, int> _partDwell = {};
  bool _voiceChecked = false;

  /// A highlight is being adjusted with its handles.
  bool _selecting = false;

  /// A context under the reader's own theme: sheets and toasts opened from
  /// here wear the picture on screen (which can differ from the app's).
  BuildContext? _themed;
  BuildContext get _ui => _themed != null && _themed!.mounted ? _themed! : context;

  @override
  void initState() {
    super.initState();
    _chromeFlag = ref.read(readerChromeProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _habit = ref.read(habitProvider.notifier);
    _sessions = ref.read(sessionLogProvider.notifier);
    _library = ref.read(libraryProvider.notifier);
    _music = ref.read(musicProvider.notifier);
    _readAloud = ref.read(readAloudProvider);
    _readAloud.waiting.addListener(_onWaiting);
    // A random track for this book (providers can change once the frame is built).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_music.start(this));
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
      // Leaving the tab: no sound or voice in other tabs; count this reel
      // (just after: providers can't change while widgets are building).
      unawaited(_music.hold());
      if (_tts) _toggleTts();
      _recordCurrent(deferred: true);
    } else {
      _shownAt = ReaderScreen.clock();
      unawaited(_music.release());
    }
  }

  /// Music on or off (options sheet): the setting, and the player with it.
  void _toggleMusic() {
    final on = !ref.read(settingsProvider).music;
    Haptics.select();
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(music: on));
    if (on != ref.read(musicProvider).playing) unawaited(_music.toggle());
  }

  /// Reads on [b] from now on: its colours are measured first, so it never
  /// shows with the wrong ones.
  Future<void> _setBackdrop(Backdrop b) async {
    if (b == _backdrop) return;
    Haptics.select();
    final asset = b.asset;
    if (asset != null) {
      try {
        await ref.read(pictureLookProvider(pictureLookKey(asset, MediaQuery.sizeOf(context))).future);
      } catch (_) {
        if (mounted) showKitToast(_ui, 'Couldn’t open that picture', icon: Icons.broken_image_outlined);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _backdrop = b);
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(lastBackdrop: b.id));
  }

  /// Measures every picture's colours once the strip is first shown, so
  /// picking one is instant.
  void _warmLooks() {
    if (_looksWarmed) return;
    final all = ref.read(backdropsProvider).value;
    if (all == null) return;
    _looksWarmed = true;
    final size = MediaQuery.sizeOf(context);
    for (final b in all) {
      if (b.asset != null) ref.read(pictureLookProvider(pictureLookKey(b.asset!, size)).future).ignore();
    }
  }

  @override
  void dispose() {
    // The tab bar shows again once the reader is gone.
    final flag = _chromeFlag;
    Future.microtask(() => flag.set(false));
    // Providers can't be modified while the tree is being torn down, so the
    // last card's reading time is recorded right after.
    _recordCurrent(deferred: true);
    final music = _music, me = this;
    scheduleMicrotask(() => music.stop(me));
    WidgetsBinding.instance.removeObserver(this);
    _chromeTimer?.cancel();
    _pager?.dispose();
    _readAloud.waiting.removeListener(_onWaiting);
    unawaited(_readAloud.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // No music while the app is in the background.
      unawaited(_music.hold());
      _recordCurrent();
      final habit = ref.read(habitProvider);
      final notifier = ref.read(habitProvider.notifier);
      if (!habit.today(DateTime.now()).meets(ref.read(settingsProvider).goal)) {
        ReminderService.instance.scheduleStreakNudge(streak: notifier.displayStreak(), freezesLeft: notifier.freezesLeft());
      }
    } else if (state == AppLifecycleState.resumed && _visible) {
      _shownAt = ReaderScreen.clock();
      unawaited(_music.release());
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
    _bodyWords = book.chapters.where((c) => c.index >= book.bodyStart).fold(0, (n, c) => n + c.wordCount);
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
    // Never under a finger: a feed that changes mid-swipe waits for the page to rest.
    if (_scrolling && _feed.isNotEmpty) {
      _feedStale = true;
      return;
    }
    final feed = buildFeed(
      book,
      segments,
      FeedOptions(
        recallCards: s.recallCards,
        reflectCards: s.reflectCards,
        // Short cards: a quick check every ~15 cards instead of ~10.
        recallEvery: s.cardLength == CardLength.snack ? 15 : 10,
        maxReelWords: maxReelWords,
      ),
      cache: _feedCache,
    );
    int index;
    if (_feed.isNotEmpty) {
      // Rebuilt (recaps arrived, the AI's cut, a new text size): the same reel.
      index = feedIndexAfterRebuild(_feed, _page, feed);
    } else {
      // Where the reader is: an explicit start, or the saved position.
      final (String? anchor, int offset) =
          widget.startSid != null ? (widget.startSid, 0) : (meta?.positionSid, meta?.positionOffset ?? 0);
      index = feedIndexForSid(feed, anchor, offset: offset);
      // A book opened for the first time starts at its own text (the
      // introduction or first chapter), past the title page and copyright.
      if (anchor == null) index = math.max(0, feed.indexWhere((f) => f.chapterIndex >= book.bodyStart));
      _shownAt = ReaderScreen.clock(); // reading starts once there's something to read
    }
    _feed = feed;
    _feedKey = key;
    _feedStale = false;
    if (_partDwell.length > 64) _partDwell.clear();
    // The pager follows in the same frame, so no frame shows the wrong reel.
    if (_pager == null || index != _page) {
      if (_pager != null && feed.isNotEmpty) _steady = feed[index];
      _newPager(index);
    }
    _page = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRequestAi(book);
    });
  }

  /// A pager that starts on [page]. The page view is rebuilt on it (a new
  /// key), and the old pager is let go once that frame is done.
  void _newPager(int page) {
    final old = _pager;
    _pager = PageController(initialPage: page, keepPage: false);
    _pagerGeneration++;
    _scrolling = false;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
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

  /// Ends the time on the reel on screen. A card shown as several reels
  /// (text · spotlight · text) counts once, when its last reel is left, for
  /// the reels read in this session; its credit is queued until the page
  /// rests (see [_settled]).
  void _leave() {
    if (_feed.isEmpty || _page >= _feed.length) return;
    final item = _feed[_page];
    final now = ReaderScreen.clock();
    final dwell = now.difference(_shownAt).inMilliseconds;
    _shownAt = now;
    if (item.kind != CardKind.text || item.card == null) return;
    final card = item.card!;
    if (!item.lastPart) {
      _partDwell[item] = (_partDwell[item] ?? 0) + dwell;
      return;
    }
    var total = dwell;
    var words = _wordsOf(item);
    for (var i = _page - 1; i >= 0 && identical(_feed[i].card, card); i--) {
      final earlier = _partDwell.remove(_feed[i]);
      if (earlier == null) continue; // not read in this session
      total += earlier;
      words += _wordsOf(_feed[i]);
    }
    if (total < 300) return;
    _credits.add((words: words, dwellMs: total, cardRef: '${widget.bookId.substring(0, 12)}:${card.startSid}'));
  }

  /// Credits the reading time queued so far: today's goal, the streak, the
  /// words read in this book, and this session's card in the feed. A card
  /// read too fast for reading (see `evaluateDwell`) counts toward none of
  /// them; only the place in the book moves on. Returns the record that met
  /// the goal.
  CardRecord? _creditQueued() {
    if (_credits.isEmpty) return null;
    final queued = [..._credits];
    _credits.clear();
    CardRecord? met;
    var words = 0;
    for (final c in queued) {
      final r = _habit.recordCard(words: c.words, dwellMs: c.dwellMs, bookId: widget.bookId, cardRef: c.cardRef);
      if (r.goalJustMet) met = r;
      if (!r.verified) continue;
      words += c.words;
      final meta = _meta;
      if (meta != null) {
        _sessions.record(
          bookId: widget.bookId,
          title: meta.title,
          author: meta.author,
          dwellMs: (r.minutes * 60000).round(),
          progress: meta.progress,
        );
      }
    }
    if (words > 0) _library.addWordsRead(widget.bookId, words, before: _wordsReadBefore());
    return met;
  }

  /// Words in the book's own text (the front matter left out).
  int _bodyWords = 0;

  /// For a book opened before words read were kept: an estimate from how
  /// far its reader had got.
  int _wordsReadBefore() => ((_meta?.progress ?? 0) * _bodyWords).round();

  /// The share of the book really read: words read over its words.
  double _readShare() {
    final meta = _library.byId(widget.bookId);
    if (meta == null || _bodyWords <= 0) return 1;
    return ((meta.wordsRead ?? _wordsReadBefore()) / _bodyWords).clamp(0.0, 1.0);
  }

  /// Saves the place in the book (the reel on screen, or the text before it).
  void _savePosition(BookContent book) {
    if (_feed.isEmpty) return;
    final item = _feed[_page.clamp(0, _feed.length - 1)];
    if (item.kind != CardKind.text || item.card == null) return;
    final anchor = item.anchorSid ?? item.card!.startSid;
    final at = (anchor, item.offset ?? 0);
    if (at == _savedAt) return;
    _savedAt = at;
    _library.updatePosition(widget.bookId, sid: anchor, offset: at.$2, progress: progressAt(book, anchor));
  }

  /// Leaving the reader or the app, or switching tabs: the reel on screen
  /// counts now, with anything still queued. [deferred] when providers can't
  /// be changed yet (while the reader is torn down).
  void _recordCurrent({bool deferred = false}) {
    _leave();
    if (deferred) {
      if (_credits.isNotEmpty) scheduleMicrotask(_creditQueued);
    } else {
      _creditQueued();
    }
  }

  /// A swipe moved to another reel: only what the next frame needs happens
  /// here (the new reel starts its reveal); the rest waits for [_settled].
  void _onPageChanged(int index) {
    _leave();
    _page = index;
    _shownAt = ReaderScreen.clock();
    Haptics.tick();
    if (_feed[index].kind == CardKind.text) _textCardsThisSession++;
    setState(() {});
  }

  /// The page came to rest: credit the reels read, save the place, and do
  /// what the reel on screen asks for, between swipes rather than during one.
  void _settled(BookContent book, BookMeta? meta) {
    if (!mounted || _feed.isEmpty) return;
    final met = _creditQueued();
    _savePosition(book);
    final item = _feed[_page.clamp(0, _feed.length - 1)];
    final settings = ref.read(settingsProvider);
    if (item.kind == CardKind.text && item.card != null) {
      if (!settings.goalSetupDone && !_goalSetupAsked && _textCardsThisSession >= 4) {
        _goalSetupAsked = true;
        showGoalSetup(_ui);
      }
      if (_tts && !identical(_spoken, item)) _speak(item);
    }
    _maybeRequestAi(book);
    // The end: it counts as finished only when most of it was really read.
    if (item.kind == CardKind.milestone && _readShare() >= finishedShare && _library.markFinished(widget.bookId)) {
      _habit.bookFinished();
      final api = ref.read(apiProvider);
      if (api.enabled) unawaited(api.bookFinished(book.title).catchError((_) {}));
    }
    if (met != null) _celebrate(met, book);
    if (_feedStale) setState(() {});
  }

  /// Today's goal is met: a toast that leaves on its own (reading goes on
  /// undisturbed), with the full celebration a tap away.
  void _celebrate(CardRecord record, BookContent book) {
    ReminderService.instance.cancelStreakNudge();
    Haptics.success();
    showKitToast(
      _ui,
      record.milestone != null ? '${record.milestone}-day streak! Goal done' : 'Goal done · ${record.streak}-day streak',
      emoji: '🔥',
      actionLabel: 'See',
      onAction: () => _showSessionComplete(record, book),
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _showSessionComplete(CardRecord record, BookContent book) async {
    if (!mounted) return;
    final today = ref.read(habitProvider).today(DateTime.now());
    final idea = _ideaOfTheDay();
    final choice = await showSessionComplete(
      _ui,
      cards: today.verifiedCards,
      minutes: today.minutes,
      words: today.words,
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
          goalShare(
            habit: ref.read(habitProvider),
            streak: record.streak,
            milestone: record.milestone,
            bookTitle: book.title,
            bookProgress: _meta?.progress ?? 0,
            now: DateTime.now(),
          ),
        );
      case SessionChoice.done:
        context.go('/journal');
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

  /// The texts of the next [count] reels that have words (looking a few
  /// reels on), to make their audio early.
  List<String> _reelTextsAhead(int from, {int count = 2}) => [
        for (var i = from + 1; i < _feed.length && i <= from + count + 4; i++)
          if (_feed[i].kind == CardKind.text && _feed[i].card != null) _reelText(_feed[i]),
      ].take(count).toList();

  /// The text of the reel with words before [from], if one is near.
  String? _reelTextBehind(int from) {
    for (var i = from - 1; i >= 0 && i >= from - 4; i--) {
      if (_feed[i].kind == CardKind.text && _feed[i].card != null) return _reelText(_feed[i]);
    }
    return null;
  }

  void _speak(FeedItem item) {
    _spoken = item;
    final text = _reelText(item);
    _music.duck(true);
    // The next two reels and the one before are made ready while this one plays.
    _readAloud.speak(text, ahead: _reelTextsAhead(_page), behind: _reelTextBehind(_page), onDone: () {
      _music.duck(false);
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
    Haptics.tap();
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
      _spoken = null;
      unawaited(_readAloud.stop());
      _music.duck(false);
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
    _shownAt = ReaderScreen.clock();
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
        final track = ref.watch(musicProvider).track;
        void pick(String v) => Navigator.of(context).pop(v);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          KitGroup(children: [
            KitRow(icon: Icons.image_outlined, title: 'Background', value: _backdrop?.label, onTap: () => pick('background')),
            KitSwitchRow(
              icon: s.music ? Icons.music_note_rounded : Icons.music_off_rounded,
              title: 'Music',
              subtitle: track?.label,
              value: s.music,
              onChanged: (_) => _toggleMusic(),
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
      case 'background':
        _pickBackdrop();
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

  /// Every picture to read on, larger than in the strip.
  Future<void> _pickBackdrop() async {
    final all = ref.read(backdropsProvider).value;
    if (all == null) return;
    final paper = ReadingTheme.of(effectiveReadingTheme(ref.read(settingsProvider), MediaQuery.platformBrightnessOf(context)));
    final picked = await showKitSheet<Backdrop>(
      _ui,
      title: 'Background',
      subtitle: 'A different one each time you open a book',
      builder: (context) => BackdropGrid(
        backdrops: all,
        selected: _backdrop ?? Backdrop.paper,
        paperColor: paper.background,
        onPick: (b) => Navigator.of(context).pop(b),
      ),
    );
    if (picked != null && mounted) await _setBackdrop(picked);
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
    // A random picture for this book (never the one shown last).
    final backdrops = ref.watch(backdropsProvider).value;
    if (backdrops != null && _backdrop == null) {
      final first = _backdrop = pickBackdrop(backdrops, lastId: settings.lastBackdrop, random: backdropRandom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(settingsProvider.notifier).update((x) => x.copyWith(lastBackdrop: first.id));
      });
    }
    // A picture shows once its colours are measured; one that can't be read gives way to the plain page.
    final lookAsync = _backdrop?.asset == null ? null : ref.watch(pictureLookProvider(pictureLookKey(_backdrop!.asset!, MediaQuery.sizeOf(context))));
    final look = lookAsync?.value;
    final backdrop = lookAsync != null && lookAsync.hasError ? Backdrop.paper : (_backdrop ?? Backdrop.paper);
    final readingTheme = readingThemeForPalette(paletteFor(backdrop, look), paperTheme);
    final backdropReady = _backdrop != null && (lookAsync == null || look != null || lookAsync.hasError);
    final meta = ref.watch(libraryProvider).where((b) => b.id == widget.bookId).firstOrNull;
    _meta = meta;
    final contentAsync = ref.watch(bookContentProvider(widget.bookId));
    final segmentsAsync = ref.watch(segmentsProvider((bookId: widget.bookId, length: settings.cardLength)));
    final lexicon = ref.watch(lexiconProvider).value ?? Lexicon.empty;

    Widget body;
    final error = contentAsync.error ?? segmentsAsync.error;
    if (error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open this book.\n$error', style: TextStyle(color: readingTheme.text))));
    } else if (contentAsync.value == null || segmentsAsync.value == null || !backdropReady) {
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
      body = _buildReader(book, meta, settings, readingTheme, type, lexicon, backdrops ?? const [], backdrop, paperTheme);
    }

    // The reader wears the picture on screen: its sheets, menus and controls
    // follow its light or dark text, whatever the app's own theme is.
    final theme = cachedAppTheme(
      ('reader', backdrop.id, look?.palette, paperTheme, settings.animatedBackground),
      () => Kit.forBackdrop(backdrop, paperTheme, look: look, motion: settings.animatedBackground),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readingTheme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(
        data: theme,
        child: Builder(builder: (context) {
          _themed = context;
          return _scaffold(backdropReady ? backdrop : Backdrop.paper, look, settings, paperTheme, readingTheme, body);
        }),
      ),
    );
  }

  Widget _scaffold(Backdrop backdrop, PictureLook? look, AppSettings settings, ReadingTheme paperTheme, ReadingTheme readingTheme, Widget body) {
    return Scaffold(
        backgroundColor: paperTheme.background,
        body: Stack(children: [
          // The picture or scene; crossfades when another is picked.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              child: Stack(key: ValueKey(backdrop.id), fit: StackFit.expand, children: [
                // Still while reels scroll (a scene repaints only its own slow motion).
                BackdropView(
                  backdrop: backdrop,
                  look: look,
                  animate: settings.animatedBackground,
                  paperColor: paperTheme.background,
                ),
                // The calibrated shade: stays put while reels move.
                if (readingTheme.scrim != null)
                  IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: readingTheme.scrim))),
              ]),
            ),
          ),
          Positioned.fill(child: body),
        ]),
    );
  }

  Widget _buildReader(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, BookType type, Lexicon lexicon,
      List<Backdrop> backdrops, Backdrop backdrop, ReadingTheme paper) {
    final notebook = ref.watch(notebookProvider);
    final habit = ref.watch(habitProvider);
    final today = habit.today(DateTime.now());
    final goal = s.goal;
    final padding = MediaQuery.paddingOf(context);
    final chromeColor = t.text;
    // The rail and the music sit above the tab bar while it shows, and glide
    // down into its room as it hides.
    final lift = widget.embedded && _chrome ? KitNavBar.reservedHeight - 10 : 0.0;
    final glide = Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 320);
    final current = _feed.isEmpty ? null : _feed[_page.clamp(0, _feed.length - 1)];
    final goalMet = today.meets(goal);

    // A pager rebuilt from scratch (after a spinner, say) starts on the reel the reader is on.
    if (_pager == null || (!_pager!.hasClients && _pager!.initialPage != _page)) _newPager(_page);
    // Any touch while the controls show keeps them up a little longer.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_chrome) _setChrome(true);
      },
      child: Stack(children: [
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // The page view's own scrolling (not a reel's text scrolling inside it).
          if (n.depth != 0) return false;
          if (n is ScrollStartNotification) {
            _scrolling = true;
          } else if (n is ScrollEndNotification) {
            _scrolling = false;
            _settled(book, meta);
          }
          return false;
        },
        child: PageView.builder(
          key: ValueKey(_pagerGeneration),
          controller: _pager,
          scrollDirection: Axis.vertical,
          physics: _selecting ? const NeverScrollableScrollPhysics() : const _ReelPagePhysics(),
          itemCount: _feed.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, i) => _buildItem(book, meta, s, t, type, lexicon, notebook, _feed[i], i == _page, padding),
        ),
      ),
      // Today's goal as one thin line that fills as you read: always there,
      // never in the way. While a reel is being turned into audio to read
      // aloud, a progress bar takes its place.
      Positioned(
        top: padding.top + 6,
        left: 16,
        right: 16,
        child: SpeechProgress(
          waiting: _readAloud.waiting,
          // With the controls up, the chapter's name is there: the rail's
          // Listen button says it instead.
          showLabel: !_chrome,
          color: railTone(chromeColor, Kit.activityTone(dark: t.isDark)),
          track: chromeColor.withValues(alpha: 0.22),
          ink: chromeColor,
          shadows: t.textShadows,
          // Blue as it fills, green once met (mixed with the text colour, so
          // it shows on any picture).
          child: _GoalLine(
            progress: today.progress(goal),
            color: railTone(chromeColor, goalMet ? Kit.growthTone(dark: t.isDark) : Kit.activityTone(dark: t.isDark)),
            track: chromeColor.withValues(alpha: 0.22),
          ),
        ),
      ),
      // With the controls: where you are, and the pictures to read on.
      Positioned(
        top: padding.top + 10,
        left: 0,
        right: 0,
        child: FadeChrome(
          visible: _chrome,
          slide: const Offset(0, -0.25),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TopBar(
                color: chromeColor,
                shadows: t.textShadows,
                title: current == null ? book.title : book.chapters[current.chapterIndex].title,
                subtitle: current?.cardsInChapter == null
                    ? book.title
                    : '${book.title} · ${(current!.cardIndexInChapter ?? 0) + 1} / ${current.cardsInChapter}',
              ),
            ),
            if (backdrops.isNotEmpty)
              BackdropStrip(
                backdrops: backdrops,
                selected: backdrop,
                ink: chromeColor,
                paperColor: paper.background,
                onPick: _setBackdrop,
              ),
          ]),
        ),
      ),
      // With the controls: the music, at the bottom left (where a reel's
      // account line would be), beside the rail.
      AnimatedPositioned(
        duration: glide,
        curve: Curves.easeOutCubic,
        left: s.leftHanded ? 72 : 16,
        right: s.leftHanded ? 16 : 72,
        bottom: padding.bottom + 22 + lift,
        child: FadeChrome(
          visible: _chrome,
          slide: const Offset(0, 0.5),
          child: _MusicBar(color: chromeColor, shadows: t.textShadows),
        ),
      ),
      if (!s.gestureTutorialSeen && _feed.isNotEmpty)
        Positioned.fill(
          child: _GestureGuide(
            onDone: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(gestureTutorialSeen: true)),
          ),
        ),
    ]),
    );
  }

  Widget _buildItem(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, BookType type, Lexicon lexicon,
      NotebookState notebook, FeedItem item, bool active, EdgeInsets padding) {
    final card = _card(book, meta, s, t, type, lexicon, notebook, item, active, padding);
    if (item.kind == CardKind.text) return card;
    // Chapter, recap, quiz and other cards: the same empty-space gestures.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _setChrome(!_chrome),
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
          settings: s,
          theme: t,
          lexicon: lexicon,
          active: active,
          animateIn: !identical(item, _steady),
          // Likes and saves belong to the reel on screen (the card, or one part of it).
          liked: notebook.liked.contains('${widget.bookId}|${item.anchorSid}'),
          saved: notebook.isSaved(widget.bookId, item.anchorSid!),
          listening: _tts,
          preparing: _tts && _preparing,
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
          streak: ref.read(habitProvider.notifier).displayStreak(),
          goalLabel: s.goal.unit == GoalUnit.cards
              ? '${today.verifiedCards}/${s.goal.dailyTarget}'
              : '${today.minutes.floor()}/${s.goal.dailyTarget}m',
          goalDone: today.meets(s.goal),
          onStreak: () => showStreakSheet(_ui),
          onGoal: () => showGoalSheet(_ui),
          onOptions: () => _options(book, s, t),
          onTapEmpty: () => _setChrome(!_chrome),
          // In the Reading tab the tab bar shows with the controls: keep the rail above it.
          railLift: widget.embedded && _chrome ? KitNavBar.reservedHeight - 10 : 0.0,
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
          onAnswered: (_) => Haptics.select(),
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
        final finished = meta?.finishedAt != null;
        final share = finished ? 1.0 : _readShare();
        return MilestoneCardView(
          bookTitle: book.title,
          readShare: finished || share >= finishedShare ? null : share,
          settings: s,
          theme: t,
          type: type,
          onShare: () {
            final meta = _library.byId(widget.bookId);
            if (meta == null) return;
            showShareSheet(
              _ui,
              bookShare(
                book: meta,
                sessions: ref.read(sessionLogProvider),
                streak: _habit.displayStreak(),
                booksFinished: math.max(ref.read(habitProvider).booksFinished, ref.read(libraryProvider).where((b) => b.finishedAt != null).length),
              ),
            );
          },
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

/// While a reel is turned into audio to read aloud: a bar across the top
/// that slides along over the time it should take (it slows as it nears the
/// end rather than stopping, and fills once the audio starts), with a line
/// saying what's happening. Otherwise [child] (today's goal line).
class SpeechProgress extends StatefulWidget {
  const SpeechProgress({
    super.key,
    required this.waiting,
    required this.color,
    required this.track,
    required this.ink,
    required this.child,
    this.shadows,
    this.showLabel = true,
  });

  final ValueListenable<SpeechWait?> waiting;

  /// Say what's happening under the bar.
  final bool showLabel;
  final Color color;
  final Color track;
  final Color ink;
  final List<Shadow>? shadows;
  final Widget child;

  /// How far along the bar is [elapsed] into a wait [expected] to take this
  /// long: most of the way at the expected time, never quite at the end.
  static double progressAt(Duration elapsed, Duration expected) {
    final t = elapsed.inMicroseconds / math.max(1, expected.inMicroseconds);
    return 0.95 * (1 - math.exp(-2.2 * t));
  }

  @override
  State<SpeechProgress> createState() => _SpeechProgressState();
}

class _SpeechProgressState extends State<SpeechProgress> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  SpeechWait? _wait;
  double _value = 0;

  @override
  void initState() {
    super.initState();
    widget.waiting.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(SpeechProgress old) {
    super.didUpdateWidget(old);
    if (!identical(old.waiting, widget.waiting)) {
      old.waiting.removeListener(_changed);
      widget.waiting.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.waiting.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  void _changed() {
    final wait = widget.waiting.value;
    if (wait == _wait) return;
    _ticker.stop();
    if (wait != null) _ticker.start();
    if (mounted) {
      setState(() {
        _wait = wait;
        _value = 0;
      });
    }
  }

  void _tick(Duration elapsed) {
    final wait = _wait;
    if (wait == null) return;
    setState(() => _value = SpeechProgress.progressAt(elapsed, wait.expected));
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      child: wait == null
          ? KeyedSubtree(key: const ValueKey('goal'), child: widget.child)
          : Semantics(
              key: const ValueKey('speech'),
              liveRegion: true,
              label: 'Converting text to audio',
              value: '${(_value * 100).round()}%',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                KitProgress(value: _value, height: 3, color: widget.color, track: widget.track),
                if (widget.showLabel) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.graphic_eq_rounded, size: 14, color: widget.ink, shadows: widget.shadows),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text('Converting text to audio…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: widget.ink, fontSize: 12, fontWeight: FontWeight.w700, shadows: widget.shadows)),
                    ),
                  ]),
                ],
              ]),
            ),
    );
  }
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

/// With the controls showing: the chapter you're in, and the book with your
/// place in the chapter. (No close button: switch tabs to leave.)
class _TopBar extends StatelessWidget {
  const _TopBar({required this.color, required this.shadows, required this.title, required this.subtitle});

  final Color color;
  final List<Shadow>? shadows;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15, shadows: shadows)),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 12.5, fontWeight: FontWeight.w600, shadows: shadows)),
        ]),
      );
}

/// What's playing, at the bottom: a note, the track and its artist, then
/// previous, play/pause and next. Nothing when there's no music.
class _MusicBar extends ConsumerWidget {
  const _MusicBar({required this.color, required this.shadows});

  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(musicProvider.select((m) => m.track));
    if (track == null) return const SizedBox.shrink();
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5)),
        child: Icon(Icons.music_note_rounded, size: 18, color: color, shadows: shadows),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Semantics(
          label: 'Playing ${track.label}',
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14.5, shadows: shadows)),
            if (track.artist != null)
              Text(track.artist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12.5, shadows: shadows)),
          ]),
        ),
      ),
      _MusicControls(color: color, shadows: shadows),
    ]);
  }
}

/// Previous, play/pause and next.
class _MusicControls extends ConsumerWidget {
  const _MusicControls({required this.color, required this.shadows});

  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(musicProvider);
    final player = ref.read(musicProvider.notifier);
    final track = music.track;
    if (track == null) return const SizedBox.shrink();
    Widget button(IconData icon, String label, VoidCallback onTap, {double size = 24}) => KitIconButton(
          icon: icon,
          semanticLabel: label,
          onPressed: () {
            Haptics.select();
            onTap();
          },
          glass: false,
          color: color,
          shadows: shadows,
          iconSize: size,
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.skip_previous_rounded, 'Previous track', player.previous),
      button(music.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, music.playing ? 'Pause music' : 'Play music', player.toggle, size: 28),
      button(Icons.skip_next_rounded, 'Next track', player.next),
    ]);
  }
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
      (Icons.touch_app_outlined, 'Tap empty space', 'Show the music, pictures and tabs for a few seconds'),
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

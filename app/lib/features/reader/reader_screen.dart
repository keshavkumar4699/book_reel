import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../core/models/reel_card.dart';
import '../../core/segmentation/feed_builder.dart';
import '../../core/segmentation/rule_segmenter.dart';
import '../../core/text/lexicon.dart';
import '../../data/api_client.dart';
import '../../data/habit.dart';
import '../../data/lexicon_loader.dart';
import '../../data/library.dart';
import '../../data/notebook.dart';
import '../../data/segments.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../services/notifications.dart';
import '../../services/soundtrack.dart';
import '../../services/tts.dart';
import '../../ui/theme.dart';
import '../../ui/vibes.dart';
import '../share/share_sheet.dart';
import 'cards/special_cards.dart';
import 'cards/text_card.dart';
import 'goal_setup_sheet.dart';
import 'page_mode.dart';
import 'session_complete.dart';
import 'word_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.startSid});

  final String bookId;
  final String? startSid;

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
  late final SoundtrackNotifier _soundtrack;
  Map<int, ChapterSegments>? _segments;
  bool _showNowPlaying = false;
  Timer? _nowPlayingTimer;
  final Set<int> _requestedAi = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _habit = ref.read(habitProvider.notifier);
    _soundtrack = ref.read(soundtrackProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _soundtrack.loadCatalog();
      _cueMusicForCurrent(chapterStart: true);
    });
  }

  /// Lets the AI soundtrack follow the card on screen (paid tiers).
  void _cueMusicForCurrent({bool chapterStart = false}) {
    if (!mounted || _feed.isEmpty) return;
    _cueMusic(_feed[_page.clamp(0, _feed.length - 1)], chapterStart: chapterStart);
  }

  void _cueMusic(FeedItem item, {bool chapterStart = false}) {
    final seg = _segments?[item.chapterIndex];
    final card = item.card;
    _soundtrack.onPosition(
      chapterKey: '${widget.bookId}:${item.chapterIndex}:${seg?.source.name}',
      cues: seg?.musicCues ?? const [],
      cardIndex: item.cardIndexInChapter ?? 0,
      mood: card?.mood,
      energy: card?.energy,
      chapterStart: chapterStart,
      teaser: seg?.teaser,
      bookTitle: _sentencesFor?.title,
    );
  }

  /// The scene behind the card on screen: the AI's choice for this part of
  /// the chapter when Auto is on (paid tiers), otherwise the reader's vibe.
  Vibe _sceneFor(AppSettings s) {
    if (!s.autoScene || !isPaidTier(s.tier) || s.vibe == Vibe.paper || _feed.isEmpty) return s.vibe;
    final item = _feed[_page.clamp(0, _feed.length - 1)];
    final name = _segments?[item.chapterIndex]?.sceneAt(item.cardIndexInChapter ?? 0);
    return Vibe.values.where((v) => v.name == name && v != Vibe.paper).firstOrNull ?? s.vibe;
  }

  Future<void> _onMusic() async {
    final settings = ref.read(settingsProvider);
    if (!isPaidTier(settings.tier)) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🎧 AI soundtrack', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('The AI reads the mood of every card and plays music that fits it: calm for quiet moments, '
                  'tense for a chase, hopeful when things turn around. Available on Plus, Pro and Scholar.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
                child: const Text('See plans'),
              ),
            ]),
          ),
        ),
      );
      return;
    }
    final st = ref.read(soundtrackProvider);
    if (st.loaded && st.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(st.message ?? 'No soundtrack available yet.'),
      ));
      return;
    }
    final on = !settings.soundtrack;
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(soundtrack: on));
    if (on) {
      await _soundtrack.loadCatalog();
      _cueMusicForCurrent(chapterStart: true);
    } else {
      await _soundtrack.stop();
    }
  }

  @override
  void dispose() {
    // Providers can't be modified while the tree is being torn down, so the
    // last card's reading time is recorded right after.
    _recordCurrent(deferred: true);
    _nowPlayingTimer?.cancel();
    scheduleMicrotask(_soundtrack.stop);
    WidgetsBinding.instance.removeObserver(this);
    _pager?.dispose();
    Tts.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _recordCurrent();
      final habit = ref.read(habitProvider);
      final notifier = ref.read(habitProvider.notifier);
      if (!habit.today(DateTime.now()).meets(ref.read(settingsProvider).goal)) {
        ReminderService.instance.scheduleStreakNudge(streak: notifier.displayStreak(), freezesLeft: notifier.freezesLeft());
      }
    } else if (state == AppLifecycleState.resumed) {
      _shownAt = DateTime.now();
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
    final key = (segments, s.recallCards, s.reflectCards);
    if (_feedKey == key) return;
    final anchor = _feed.isEmpty ? (widget.startSid ?? meta?.positionSid) : _currentAnchorSid();
    _feed = buildFeed(
      book,
      segments,
      FeedOptions(
        recallCards: s.recallCards,
        reflectCards: s.reflectCards,
        // Short cards: a quick check every ~15 cards instead of ~10.
        recallEvery: s.cardLength == CardLength.snack ? 15 : 10,
      ),
    );
    _feedKey = key;
    var index = feedIndexForSid(_feed, anchor);
    if (anchor == null) index = 0;
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

  String? _currentAnchorSid() {
    for (var i = _page; i >= 0 && i < _feed.length; i--) {
      final sid = _feed[i].anchorSid;
      if (sid != null) return sid;
    }
    return null;
  }

  void _maybeRequestAi(BookContent book) async {
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

  /// Records dwell time for the card currently on screen.
  CardRecord? _recordCurrent({bool deferred = false}) {
    if (_feed.isEmpty || _page >= _feed.length) return null;
    final item = _feed[_page];
    final dwell = DateTime.now().difference(_shownAt).inMilliseconds;
    _shownAt = DateTime.now();
    if (item.kind != CardKind.text || item.card == null || dwell < 300) return null;
    CardRecord record() => _habit.recordCard(
          words: item.card!.wordCount,
          dwellMs: dwell,
          bookId: widget.bookId,
          cardRef: '${widget.bookId.substring(0, 12)}:${item.card!.startSid}',
        );
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
      ref.read(libraryProvider.notifier).updatePosition(
            widget.bookId,
            sid: item.card!.startSid,
            progress: progressAt(book, item.card!.startSid),
          );
      _textCardsThisSession++;
      if (!settings.goalSetupDone && _textCardsThisSession == 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showGoalSetup(context);
        });
      }
      if (_tts) _speak(item);
      final previous = index > 0 ? _feed[index - 1] : null;
      _cueMusic(item, chapterStart: previous?.chapterIndex != item.chapterIndex);
    }
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
      context,
      vibe: ref.read(settingsProvider).vibe,
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
          context,
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

  void _speak(FeedItem item) {
    final text = item.card!.sentenceIds.map((sid) => _sentences[sid]?.sentence.text ?? '').join(' ');
    _soundtrack.duck(true);
    Tts.instance.speak(text, onDone: () {
      _soundtrack.duck(false);
      if (mounted && _tts && _pager != null && _page < _feed.length - 1) {
        _pager!.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ---------------------------------------------------------------- actions

  List<String> _cardTexts(SegmentCard card) => [for (final sid in card.sentenceIds) _sentences[sid]?.sentence.text ?? ''];

  void _share(BookContent book, BookMeta? meta, FeedItem item) {
    final card = item.card;
    if (card == null) return;
    final notebook = ref.read(notebookProvider);
    final highlighted = [
      for (final sid in card.sentenceIds)
        if (notebook.highlightFor(widget.bookId, sid) != null || card.keySids.contains(sid)) _sentences[sid]!.sentence.text,
    ];
    showShareSheet(
      context,
      QuoteShare(
        sentences: highlighted.isNotEmpty ? highlighted : _cardTexts(card),
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
      startSid: card.startSid,
      text: _cardTexts(card).join(' '),
      createdAt: DateTime.now(),
    ));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(saved ? 'Saved to your Notebook 🔖' : 'Removed from saved'),
        duration: const Duration(milliseconds: 1600),
      ));
  }

  void _toggleHighlight(BookContent book, Sentence s) {
    final h = ref.read(notebookProvider.notifier).toggleHighlight(
          bookId: widget.bookId,
          bookTitle: book.title,
          sid: s.id,
          text: s.text,
        );
    if (h == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
        content: const Text('Highlighted ✨'),
        action: SnackBarAction(label: 'Add note', onPressed: () => _editNote(h)),
      ));
  }

  void _toggleTts() {
    setState(() => _tts = !_tts);
    if (_tts && _feed[_page].card != null) {
      _speak(_feed[_page]);
    } else {
      Tts.instance.stop();
      _soundtrack.duck(false);
    }
  }

  Future<void> _editNote(Highlight h) async {
    final controller = TextEditingController(text: h.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(controller: controller, autofocus: true, maxLines: 4, decoration: const InputDecoration(hintText: 'Your thoughts…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (note != null) ref.read(notebookProvider.notifier).updateHighlight(h.copyWith(note: note));
  }

  Future<void> _highlightSheet(BookContent book, SegmentCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final notebook = ref.watch(notebookProvider);
        final colors = ReadingTheme.of(ReadingThemeId.paper).highlights;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('Tap sentences to highlight', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final sid in card.sentenceIds)
                if (_sentences[sid] != null)
                  Builder(builder: (context) {
                    final h = notebook.highlightFor(widget.bookId, sid);
                    return ListTile(
                      tileColor: h == null ? null : colors[h.color],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      title: Text(_sentences[sid]!.sentence.text),
                      subtitle: h?.note == null || h!.note!.isEmpty ? null : Text('📝 ${h.note}'),
                      trailing: h == null
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'note') {
                                  _editNote(h);
                                } else {
                                  ref.read(notebookProvider.notifier).updateHighlight(h.copyWith(color: int.parse(v)));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'note', child: Text('Add note')),
                                for (var i = 0; i < highlightColorCount; i++)
                                  PopupMenuItem(
                                    value: '$i',
                                    child: Row(children: [
                                      CircleAvatar(radius: 8, backgroundColor: colors[i].withValues(alpha: 1)),
                                      const SizedBox(width: 8),
                                      Text(['Amber', 'Green', 'Blue', 'Pink'][i]),
                                    ]),
                                  ),
                              ],
                            ),
                      onTap: () => ref.read(notebookProvider.notifier).toggleHighlight(
                            bookId: widget.bookId,
                            bookTitle: book.title,
                            sid: sid,
                            text: _sentences[sid]!.sentence.text,
                          ),
                    );
                  }),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _openContents(BookContent book) async {
    final chapter = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            const ListTile(title: Text('Contents', style: TextStyle(fontWeight: FontWeight.w600))),
            for (final c in book.chapters)
              ListTile(
                selected: _feed.isNotEmpty && _feed[_page].chapterIndex == c.index,
                title: Text(c.title),
                subtitle: Text('~${(c.wordCount / ref.read(habitProvider).wpm).ceil()} min'),
                onTap: () => Navigator.pop(context, c.index),
              ),
          ],
        ),
      ),
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
        anchorSid: _currentAnchorSid(),
        settings: s,
        theme: theme,
      ),
    ));
    _shownAt = DateTime.now();
    if (sid != null && mounted) _pager?.jumpToPage(feedIndexForSid(_feed, sid));
  }

  void _more(BookContent book, AppSettings s, ReadingTheme theme) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.list), title: const Text('Contents'), onTap: () => Navigator.pop(context, 'toc')),
          ListTile(leading: const Icon(Icons.chrome_reader_mode_outlined), title: const Text('Page mode'), onTap: () => Navigator.pop(context, 'page')),
          ListTile(leading: const Icon(Icons.touch_app_outlined), title: const Text('Gestures'), onTap: () => Navigator.pop(context, 'gestures')),
          ListTile(leading: const Icon(Icons.text_fields), title: const Text('Reading settings'), onTap: () => Navigator.pop(context, 'settings')),
          ListTile(leading: const Icon(Icons.content_cut), title: const Text('This cut feels wrong'), onTap: () => Navigator.pop(context, 'report')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'toc':
        _openContents(book);
      case 'page':
        _openPageMode(book, s, theme);
      case 'gestures':
        ref.read(settingsProvider.notifier).update((x) => x.copyWith(gestureTutorialSeen: false));
      case 'settings':
        context.push('/settings');
      case 'report':
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanks! Reports like this help us cut cards better.')));
    }
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
    final contentAsync = ref.watch(bookContentProvider(widget.bookId));
    final segmentsAsync = ref.watch(segmentsProvider((bookId: widget.bookId, length: settings.cardLength)));
    final lexicon = ref.watch(lexiconProvider).value ?? Lexicon.empty;

    Widget body;
    final error = contentAsync.error ?? segmentsAsync.error;
    if (error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open this book.\n$error', style: TextStyle(color: readingTheme.text))));
    } else if (contentAsync.value == null || segmentsAsync.value == null) {
      body = Center(child: CircularProgressIndicator(color: readingTheme.muted));
    } else {
      final book = contentAsync.value!;
      _ensureSentences(book);
      _ensureFeed(book, segmentsAsync.value!, settings, meta);
      body = _buildReader(book, meta, settings, readingTheme, lexicon);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readingTheme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: paperTheme.background,
        body: Stack(children: [
          // AI-picked (or chosen) scene; crossfades when the story moves.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1400),
              child: VibeBackground(
                key: ValueKey(scene),
                vibe: scene,
                animate: settings.animatedBackground,
                pager: _pager,
                paperColor: paperTheme.background,
              ),
            ),
          ),
          Positioned.fill(child: body),
        ]),
      ),
    );
  }

  Widget _buildReader(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, Lexicon lexicon) {
    final notebook = ref.watch(notebookProvider);
    final habit = ref.watch(habitProvider);
    final today = habit.today(DateTime.now());
    final goal = s.goal;
    final padding = MediaQuery.paddingOf(context);
    final scene = _sceneFor(s);
    final style = vibeStyles[scene]!;
    final onScene = scene != Vibe.paper;
    final auto = s.autoScene && isPaidTier(s.tier) && s.vibe != Vibe.paper;
    final chromeColor = onScene ? Colors.white : t.text;
    final soundtrack = ref.watch(soundtrackProvider);
    ref.listen(soundtrackProvider.select((x) => x.playing?.id), (prev, next) {
      if (next == null || next == prev) return;
      setState(() => _showNowPlaying = true);
      _nowPlayingTimer?.cancel();
      _nowPlayingTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showNowPlaying = false);
      });
    });

    return Stack(children: [
      PageView.builder(
        controller: _pager,
        scrollDirection: Axis.vertical,
        physics: const _ReelPagePhysics(),
        itemCount: _feed.length,
        onPageChanged: (i) => _onPageChanged(i, book, meta),
        itemBuilder: (context, i) => _buildItem(book, meta, s, t, style, lexicon, notebook, _feed[i], i == _page, padding),
      ),
      // Segmented goal bar (Stories style): always visible, very thin.
      Positioned(
        top: padding.top + 6,
        left: 16,
        right: 16,
        child: _GoalBar(
          segments: goal.unit == GoalUnit.cards && goal.dailyTarget <= 40 ? goal.dailyTarget : 0,
          done: goal.unit == GoalUnit.cards ? today.verifiedCards : 0,
          progress: today.progress(goal),
          color: style.accent,
          track: chromeColor.withValues(alpha: 0.25),
        ),
      ),
      Positioned(
        top: padding.top + 14,
        left: 4,
        right: 4,
        child: _TopBar(
          color: chromeColor,
          accent: style.accent,
          streak: ref.read(habitProvider.notifier).displayStreak(),
          goalLabel: goal.unit == GoalUnit.cards
              ? '${today.verifiedCards}/${goal.dailyTarget}'
              : '${today.minutes.floor()}/${goal.dailyTarget} min',
          goalDone: today.meets(goal),
          vibeEmoji: auto ? '✨' : style.emoji,
          music: !isPaidTier(s.tier)
              ? _MusicButton.locked
              : (s.soundtrack && soundtrack.playing != null)
                  ? _MusicButton.playing
                  : s.soundtrack
                      ? _MusicButton.on
                      : _MusicButton.off,
          onMusic: _onMusic,
          onClose: () => context.canPop() ? context.pop() : context.go('/library'),
          onVibe: _pickVibe,
          onMore: () => _more(book, s, t),
        ),
      ),
      // "Now playing" credit (attribution is required by music licenses).
      Positioned(
        top: padding.top + 64,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showNowPlaying && soundtrack.playing != null ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  soundtrack.playing == null ? '' : '♪ ${soundtrack.playing!.attribution}  ·  ${soundtrack.mood ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
      if (!s.gestureTutorialSeen && _feed.isNotEmpty)
        Positioned.fill(
          child: _GestureGuide(
            accent: style.accent,
            onDone: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(gestureTutorialSeen: true)),
          ),
        ),
    ]);
  }

  Future<void> _pickVibe() async {
    final s = ref.read(settingsProvider);
    final paid = isPaidTier(s.tier);
    // null = Auto (the AI picks the scene for each part of the book).
    final picked = await showModalBottomSheet<(Vibe?,)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pick your vibe', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              paid ? 'Auto lets the AI choose the scene that fits each chapter.' : 'Auto (AI-picked scenes) is part of Plus, Pro and Scholar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            VibePickerRow(
              selected: s.vibe,
              autoSelected: paid && s.autoScene && s.vibe != Vibe.paper,
              onAuto: paid ? () => Navigator.pop(context, (null,)) : null,
              onSelected: (v) => Navigator.pop(context, (v,)),
            ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    final vibe = picked.$1;
    ref.read(settingsProvider.notifier).update((x) => vibe == null ? x.copyWith(autoScene: true) : x.copyWith(vibe: vibe, autoScene: false));
  }

  Widget _buildItem(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, VibeStyle style, Lexicon lexicon,
      NotebookState notebook, FeedItem item, bool active, EdgeInsets padding) {
    switch (item.kind) {
      case CardKind.text:
        final card = item.card!;
        return PostCard(
          key: ValueKey('${card.startSid}-${s.cardLength.name}'),
          card: card,
          sentences: [for (final sid in card.sentenceIds) if (_sentences[sid] != null) _sentences[sid]!],
          bookTitle: book.title,
          chapterTitle: book.chapters[card.chapterIndex].title,
          position: '${(item.cardIndexInChapter ?? 0) + 1} / ${item.cardsInChapter ?? 0}',
          coverPath: meta?.coverPath,
          settings: s,
          theme: t,
          accent: style.accent,
          lexicon: lexicon,
          active: active,
          liked: notebook.liked.contains('${widget.bookId}|${card.startSid}'),
          saved: notebook.isSaved(widget.bookId, card.startSid),
          listening: _tts,
          highlightFor: (sid) => notebook.highlightFor(widget.bookId, sid),
          onToggleHighlight: (sentence) => _toggleHighlight(book, sentence),
          onLongPressWord: (word, sentence) {
            final meaning = card.hardWords
                .where((h) => h.word.toLowerCase() == word.toLowerCase() && h.meaning != null)
                .map((h) => h.meaning)
                .firstOrNull;
            showWordSheet(context,
                word: word, sentence: sentence.text, bookTitle: book.title, lexicon: lexicon, contextMeaning: meaning);
          },
          onLike: () => ref.read(notebookProvider.notifier).toggleLike(widget.bookId, card.startSid),
          onSave: () => _toggleSave(book, item),
          onShare: () => _share(book, meta, item),
          onNote: () => _highlightSheet(book, card),
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
        );
      case CardKind.recap:
        return RecapCardView(bullets: item.recapBullets!, settings: s, theme: t);
      case CardKind.recall:
        return RecallCardView(
          settings: s,
          theme: t,
          question: item.recall,
          revealSentences: [for (final sid in item.recallSids ?? const <String>[]) _sentences[sid]?.sentence.text ?? ''],
          onAnswered: (_) => HapticFeedback.selectionClick(),
        );
      case CardKind.reflect:
        return ReflectCardView(
          settings: s,
          theme: t,
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
          onShare: () => showShareSheet(
            context,
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

class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.segments, required this.done, required this.progress, required this.color, required this.track});

  final int segments;
  final int done;
  final double progress;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Today\'s goal ${(progress * 100).round()} percent',
      child: SizedBox(
        height: 3,
        child: segments == 0
            ? ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress, color: color, backgroundColor: track),
              )
            : Row(children: [
                for (var i = 0; i < segments; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(color: i < done ? color : track, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ],
              ]),
      ),
    );
  }
}

enum _MusicButton { locked, off, on, playing }

/// Top bar: close · streak flame · today's goal · soundtrack · vibe switcher · menu.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.color,
    required this.accent,
    required this.streak,
    required this.goalLabel,
    required this.goalDone,
    required this.vibeEmoji,
    required this.music,
    required this.onMusic,
    required this.onClose,
    required this.onVibe,
    required this.onMore,
  });

  final Color color;
  final Color accent;
  final int streak;
  final String goalLabel;
  final bool goalDone;
  final String vibeEmoji;
  final _MusicButton music;
  final VoidCallback onMusic;
  final VoidCallback onClose;
  final VoidCallback onVibe;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 8)];
    Widget pill(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(20)),
          child: child,
        );
    return Row(children: [
      IconButton(tooltip: 'Close', icon: Icon(Icons.close, color: color, shadows: shadow), onPressed: onClose),
      const Spacer(),
      pill(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department, size: 18, color: streak > 0 ? accent : color.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text('$streak', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ])),
      const SizedBox(width: 8),
      pill(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(goalDone ? Icons.check_circle : Icons.flag_outlined, size: 16, color: goalDone ? accent : color),
        const SizedBox(width: 4),
        Text(goalLabel, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ])),
      const Spacer(),
      IconButton(
        tooltip: switch (music) {
          _MusicButton.locked => 'AI soundtrack (paid plans)',
          _MusicButton.off => 'Turn on soundtrack',
          _ => 'Turn off soundtrack',
        },
        onPressed: onMusic,
        icon: Icon(
          switch (music) {
            _MusicButton.playing => Icons.music_note,
            _MusicButton.on => Icons.music_note_outlined,
            _MusicButton.off => Icons.music_off_outlined,
            _MusicButton.locked => Icons.headphones_outlined,
          },
          color: music == _MusicButton.playing ? accent : color,
          shadows: shadow,
        ),
      ),
      IconButton(tooltip: 'Change vibe', onPressed: onVibe, icon: Text(vibeEmoji, style: const TextStyle(fontSize: 20))),
      IconButton(tooltip: 'More', icon: Icon(Icons.more_horiz, color: color, shadows: shadow), onPressed: onMore),
    ]);
  }
}

/// One-time overlay that teaches the gestures (can be reopened from ⋯).
class _GestureGuide extends StatelessWidget {
  const _GestureGuide({required this.accent, required this.onDone});
  final Color accent;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    const rows = [
      (Icons.swipe_up_outlined, 'Swipe up', 'Next card'),
      (Icons.favorite, 'Double-tap', 'Like'),
      (Icons.touch_app_outlined, 'Tap a sentence', 'Highlight it'),
      (Icons.swipe_left_outlined, 'Swipe left', 'Save'),
      (Icons.swipe_right_outlined, 'Swipe right', 'Share'),
      (Icons.translate, 'Long-press a word', 'See its meaning'),
    ];
    return GestureDetector(
      onTap: onDone,
      child: Container(
        color: const Color(0xCC0B0F14),
        padding: const EdgeInsets.all(32),
        child: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Read like you scroll',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: accent.withValues(alpha: 0.2), child: Icon(r.$1, color: accent)),
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
            FilledButton(onPressed: onDone, style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black), child: const Text('Got it')),
          ]),
        ),
      ),
    );
  }
}

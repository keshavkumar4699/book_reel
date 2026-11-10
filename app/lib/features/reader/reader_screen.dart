import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../core/models/reel_card.dart';
import '../../core/segmentation/feed_builder.dart';
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
import '../../services/tts.dart';
import '../../ui/theme.dart';
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
  bool _chrome = true;
  Timer? _chromeTimer;
  bool _tts = false;
  int _textCardsThisSession = 0;
  final Set<int> _requestedAi = {};

  static const _hints = [
    'Swipe up for the next card',
    'Long-press any word to see its meaning',
    'Double-tap a sentence to highlight it',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleChromeHide();
  }

  @override
  void dispose() {
    _recordCurrent();
    WidgetsBinding.instance.removeObserver(this);
    _chromeTimer?.cancel();
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
    _feed = buildFeed(book, segments, FeedOptions(recallCards: s.recallCards, reflectCards: s.reflectCards));
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
  CardRecord? _recordCurrent() {
    if (_feed.isEmpty || _page >= _feed.length) return null;
    final item = _feed[_page];
    final dwell = DateTime.now().difference(_shownAt).inMilliseconds;
    _shownAt = DateTime.now();
    if (item.kind != CardKind.text || item.card == null || dwell < 300) return null;
    return ref.read(habitProvider.notifier).recordCard(
          words: item.card!.wordCount,
          dwellMs: dwell,
          bookId: widget.bookId,
          cardRef: '${widget.bookId.substring(0, 12)}:${item.card!.startSid}',
        );
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

  // ---------------------------------------------------------------- chrome

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleChromeHide();
  }

  void _speak(FeedItem item) {
    final text = item.card!.sentenceIds.map((sid) => _sentences[sid]?.sentence.text ?? '').join(' ');
    Tts.instance.speak(text, onDone: () {
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
      ..showSnackBar(SnackBar(content: Text(saved ? 'Saved to your Notebook' : 'Removed from saved'), duration: const Duration(seconds: 2)));
  }

  void _onDoubleTapSentence(BookContent book, Sentence s) {
    HapticFeedback.lightImpact();
    final h = ref.read(notebookProvider.notifier).toggleHighlight(
          bookId: widget.bookId,
          bookTitle: book.title,
          sid: s.id,
          text: s.text,
        );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(h == null ? 'Highlight removed' : 'Highlighted'),
        action: h == null ? null : SnackBarAction(label: 'Add note', onPressed: () => _editNote(h)),
      ));
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
          ListTile(
            leading: Icon(_tts ? Icons.stop_circle_outlined : Icons.record_voice_over_outlined),
            title: Text(_tts ? 'Stop reading aloud' : 'Read aloud'),
            onTap: () => Navigator.pop(context, 'tts'),
          ),
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
      case 'tts':
        setState(() => _tts = !_tts);
        if (_tts && _feed[_page].card != null) {
          _speak(_feed[_page]);
        } else {
          Tts.instance.stop();
        }
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
    final readingTheme = ReadingTheme.of(effectiveReadingTheme(settings, MediaQuery.platformBrightnessOf(context)));
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
      child: Scaffold(backgroundColor: readingTheme.background, body: body),
    );
  }

  Widget _buildReader(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, Lexicon lexicon) {
    final notebook = ref.watch(notebookProvider);
    final habit = ref.watch(habitProvider);
    final today = habit.today(DateTime.now());
    final goal = s.goal;
    final item = _feed.isEmpty ? null : _feed[_page.clamp(0, _feed.length - 1)];
    final chapter = item == null ? null : book.chapters[item.chapterIndex];
    final padding = MediaQuery.paddingOf(context);
    final firstChapter = book.chapters.first.index;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleChrome,
      child: Stack(children: [
        PageView.builder(
          controller: _pager,
          scrollDirection: Axis.vertical,
          physics: const _ReelPagePhysics(),
          itemCount: _feed.length,
          onPageChanged: (i) => _onPageChanged(i, book, meta),
          itemBuilder: (context, i) => _buildItem(book, meta, s, t, lexicon, notebook, _feed[i], firstChapter, padding),
        ),
        // Segmented goal bar: always visible, very thin (goal-gradient effect).
        Positioned(
          top: padding.top + 6,
          left: 16,
          right: 16,
          child: _GoalBar(
            segments: goal.unit == GoalUnit.cards && goal.dailyTarget <= 30 ? goal.dailyTarget : 0,
            done: goal.unit == GoalUnit.cards ? today.verifiedCards : 0,
            progress: today.progress(goal),
            color: ember,
            track: t.muted.withValues(alpha: 0.25),
          ),
        ),
        // Fading chrome: top labels.
        Positioned(
          top: padding.top + 14,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_chrome,
            child: AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Row(children: [
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: t.muted),
                  onPressed: () => context.canPop() ? context.pop() : context.go('/library'),
                ),
                Expanded(
                  child: Text(
                    chapter?.title ?? book.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${((meta?.progress ?? 0) * 100).round()}%', style: TextStyle(color: t.muted, fontSize: 13)),
                ),
              ]),
            ),
          ),
        ),
        // Fading chrome: bottom action row in the thumb zone.
        if (item != null && item.kind == CardKind.text)
          Positioned(
            bottom: padding.bottom + 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0.35,
                duration: const Duration(milliseconds: 200),
                child: _ActionRow(
                  leftHanded: s.leftHanded,
                  color: t.text,
                  liked: notebook.liked.contains('${widget.bookId}|${item.card!.startSid}'),
                  saved: notebook.isSaved(widget.bookId, item.card!.startSid),
                  onLike: () {
                    HapticFeedback.lightImpact();
                    ref.read(notebookProvider.notifier).toggleLike(widget.bookId, item.card!.startSid);
                  },
                  onHighlight: () => _highlightSheet(book, item.card!),
                  onSave: () => _toggleSave(book, item),
                  onShare: () => _share(book, meta, item),
                  onMore: () => _more(book, s, t),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildItem(BookContent book, BookMeta? meta, AppSettings s, ReadingTheme t, Lexicon lexicon,
      NotebookState notebook, FeedItem item, int firstChapter, EdgeInsets padding) {
    switch (item.kind) {
      case CardKind.text:
        final card = item.card!;
        final hintIndex = !s.goalSetupDone && item.chapterIndex == firstChapter ? item.cardIndexInChapter! : 99;
        return TextCardView(
          key: ValueKey('${card.startSid}-${s.cardLength.name}'),
          card: card,
          sentences: [for (final sid in card.sentenceIds) if (_sentences[sid] != null) _sentences[sid]!],
          chapterTitle: book.chapters[card.chapterIndex].title,
          settings: s,
          theme: t,
          lexicon: lexicon,
          topPadding: padding.top + 64,
          bottomPadding: padding.bottom + 88,
          hint: hintIndex < _hints.length ? _hints[hintIndex] : null,
          highlightFor: (sid) => notebook.highlightFor(widget.bookId, sid),
          onDoubleTapSentence: (sentence) => _onDoubleTapSentence(book, sentence),
          onLongPressWord: (word, sentence) {
            final meaning = card.hardWords
                .where((h) => h.word.toLowerCase() == word.toLowerCase() && h.meaning != null)
                .map((h) => h.meaning)
                .firstOrNull;
            showWordSheet(context,
                word: word, sentence: sentence.text, bookTitle: book.title, lexicon: lexicon, contextMeaning: meaning);
          },
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
              lines: [
                'by ${book.author}',
                '${_feed.where((f) => f.kind == CardKind.text).length} reels',
              ],
            ),
          ),
          onDone: () => context.go('/library'),
        );
    }
  }
}

/// Page physics with slight resistance so cards feel like page turns, not a
/// slippery feed (UX_DESIGN.md §5.2).
class _ReelPagePhysics extends PageScrollPhysics {
  const _ReelPagePhysics({super.parent});

  @override
  _ReelPagePhysics applyTo(ScrollPhysics? ancestor) => _ReelPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => const SpringDescription(mass: 1, stiffness: 120, damping: 22);

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
                  if (i > 0) const SizedBox(width: 3),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.leftHanded,
    required this.color,
    required this.liked,
    required this.saved,
    required this.onLike,
    required this.onHighlight,
    required this.onSave,
    required this.onShare,
    required this.onMore,
  });

  final bool leftHanded;
  final Color color;
  final bool liked;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onHighlight;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      IconButton(
          tooltip: liked ? 'Unlike' : 'Like',
          onPressed: onLike,
          icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? ember : color)),
      IconButton(tooltip: 'Highlight & note', onPressed: onHighlight, icon: Icon(Icons.border_color_outlined, color: color)),
      IconButton(
          tooltip: saved ? 'Saved' : 'Save',
          onPressed: onSave,
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: saved ? ember : color)),
      IconButton(tooltip: 'Share', onPressed: onShare, icon: Icon(Icons.ios_share, color: color)),
      IconButton(tooltip: 'More', onPressed: onMore, icon: Icon(Icons.more_horiz, color: color)),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: leftHanded ? buttons.reversed.toList() : buttons,
    );
  }
}

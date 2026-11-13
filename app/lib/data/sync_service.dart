import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import '../core/habit/habit_engine.dart' show GoalUnit;
import 'library.dart';
import 'notebook.dart';
import 'settings_provider.dart';
import 'store_provider.dart';

/// One syncable record: `kind` + `id` → JSON data.
typedef SyncRecord = ({String kind, String id, Object? data});

/// Flattens the notebook into syncable records (server/src/social/sync.ts kinds).
List<SyncRecord> notebookRecords(NotebookState n) => [
      for (final h in n.highlights) (kind: 'highlight', id: h.id, data: h.toJson()),
      for (final s in n.saved) (kind: 'saved', id: s.id, data: s.toJson()),
      for (final w in n.words) (kind: 'word', id: w.word, data: w.toJson()),
      for (final r in n.reflections) (kind: 'reflection', id: r.id, data: r.toJson()),
      for (final l in n.liked) (kind: 'like', id: l, data: true),
    ];

/// Applies pulled records to a notebook: upserts and tombstones.
NotebookState applyRemote(NotebookState n, List<Map<String, dynamic>> items) {
  final highlights = {for (final h in n.highlights) h.id: h};
  final saved = {for (final s in n.saved) s.id: s};
  final words = {for (final w in n.words) w.word: w};
  final reflections = {for (final r in n.reflections) r.id: r};
  final liked = {...n.liked};
  for (final item in items) {
    final id = item['id'] as String;
    final deleted = item['deleted'] == true;
    final data = item['data'];
    switch (item['kind']) {
      case 'highlight':
        deleted ? highlights.remove(id) : highlights[id] = Highlight.fromJson(data as Map<String, dynamic>);
      case 'saved':
        deleted ? saved.remove(id) : saved[id] = SavedCard.fromJson(data as Map<String, dynamic>);
      case 'word':
        deleted ? words.remove(id) : words[id] = WordEntry.fromJson(data as Map<String, dynamic>);
      case 'reflection':
        deleted ? reflections.remove(id) : reflections[id] = Reflection.fromJson(data as Map<String, dynamic>);
      case 'like':
        deleted ? liked.remove(id) : liked.add(id);
    }
  }
  int newestFirst(DateTime a, DateTime b) => b.compareTo(a);
  return NotebookState(
    highlights: highlights.values.toList()..sort((a, b) => newestFirst(a.createdAt, b.createdAt)),
    saved: saved.values.toList()..sort((a, b) => newestFirst(a.createdAt, b.createdAt)),
    words: words.values.toList()..sort((a, b) => newestFirst(a.addedAt, b.addedAt)),
    reflections: reflections.values.toList()..sort((a, b) => newestFirst(a.createdAt, b.createdAt)),
    liked: liked,
  );
}

String _hash(Object? data) => sha1.convert(utf8.encode(jsonEncode(data))).toString().substring(0, 16);

/// Background sync with the Cloro server (IMPLEMENTATION_PLAN.md Phase 7):
/// uploads queued reading events (for server-verified streaks and leagues),
/// and syncs the notebook and reading positions across devices. Pull first,
/// then push local changes; the server keeps the newest write per item.
class SyncService {
  SyncService(this.ref);
  final Ref ref;
  Timer? _timer;
  Future<void>? _running;

  BookReelApi get _api => ref.read(apiProvider);

  void start() {
    if (!_api.enabled || _timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    syncNow();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs one sync pass; concurrent calls share the pass in progress.
  Future<void> syncNow() {
    if (!_api.enabled) return Future.value();
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  Future<void> _sync() async {
    try {
      await syncProfile();
      await flushActivity();
      await syncNotebook();
      await syncPositions();
    } catch (e) {
      debugPrint('Sync skipped: $e'); // offline or server error: retry on the next pass
    }
  }

  /// Name, daily goal and freezes, so the server's goal/streak checks match the app.
  Future<void> syncProfile() async {
    final s = ref.read(settingsProvider);
    final profile = {
      'name': s.displayName,
      'goal': s.goalUnit == GoalUnit.cards ? s.dailyGoal : 10,
      'freezes': s.tier.freezes,
      'handle': s.username,
      'pronouns': s.pronouns,
      'bio': s.bio,
      'avatar': s.avatarEmoji,
    };
    final store = ref.read(storeProvider);
    final syncDoc = Map<String, dynamic>.from(store.doc('sync') ?? const {});
    final h = _hash(profile);
    if (syncDoc['profile'] == h) return;
    Future<void> send({required bool withHandle}) => _api.updateProfile(
          displayName: profile['name'] as String,
          dailyGoalCards: profile['goal'] as int,
          freezesPerWeek: profile['freezes'] as int,
          handle: withHandle ? profile['handle'] as String : null,
          pronouns: profile['pronouns'] as String,
          bio: profile['bio'] as String,
          avatar: profile['avatar'] as String,
        );
    try {
      await send(withHandle: true);
    } on ApiException catch (e) {
      // Someone took the username meanwhile: keep it on the phone and sync the
      // rest, so the other syncs aren't blocked. (Profile edits check names first.)
      if (e.status != 409 && e.status != 400) rethrow;
      await send(withHandle: false);
    }
    await store.saveDoc('sync', {...syncDoc, 'profile': h});
  }

  Future<void> flushActivity() async {
    final store = ref.read(storeProvider);
    final events = ((store.doc('outbox')?['events'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (events.isEmpty) return;
    for (var i = 0; i < events.length; i += 500) {
      final chunk = events.sublist(i, i + 500 > events.length ? events.length : i + 500);
      await _api.uploadActivity(chunk);
      // Remove only what was sent; new events may have been queued meanwhile.
      final current = ((store.doc('outbox')?['events'] as List?) ?? const []).cast<Map<String, dynamic>>();
      await store.saveDoc('outbox', {'events': current.skip(chunk.length).toList()});
    }
  }

  Future<void> syncNotebook() async {
    final store = ref.read(storeProvider);
    final syncDoc = Map<String, dynamic>.from(store.doc('sync') ?? const {});
    var cursor = (syncDoc['cursor'] as int?) ?? 0;
    final pushed = Map<String, String>.from((syncDoc['pushed'] as Map?) ?? const {});

    // 1. Pull remote changes.
    final pulled = <Map<String, dynamic>>[];
    while (true) {
      final page = await _api.pullSync(cursor);
      final items = (page['items'] as List).cast<Map<String, dynamic>>();
      pulled.addAll(items);
      cursor = page['cursor'] as int;
      if (page['more'] != true) break;
    }
    final notebookItems = pulled.where((i) => i['kind'] != 'position').toList();
    final local = notebookRecords(ref.read(notebookProvider));
    final localHashes = {for (final r in local) '${r.kind}|${r.id}': _hash(r.data)};
    // A record edited locally since the last push wins over the pulled copy;
    // it is pushed below with a newer timestamp.
    final applicable = notebookItems.where((i) {
      final key = '${i['kind']}|${i['id']}';
      final dirty = localHashes.containsKey(key) && localHashes[key] != pushed[key];
      return !dirty;
    }).toList();
    if (applicable.isNotEmpty) {
      ref.read(notebookProvider.notifier).replace(applyRemote(ref.read(notebookProvider), applicable));
      for (final i in applicable) {
        final key = '${i['kind']}|${i['id']}';
        if (i['deleted'] == true) {
          pushed.remove(key);
        } else {
          pushed[key] = _hash(i['data']);
        }
      }
    }
    _pendingPositions = pulled.where((i) => i['kind'] == 'position').toList();

    // 2. Push local changes and deletions.
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = notebookRecords(ref.read(notebookProvider));
    final currentKeys = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final r in current) {
      final key = '${r.kind}|${r.id}';
      currentKeys.add(key);
      final h = _hash(r.data);
      if (pushed[key] != h) {
        out.add({'kind': r.kind, 'id': r.id, 'updated_at': now, 'deleted': false, 'data': r.data});
        pushed[key] = h;
      }
    }
    for (final key in pushed.keys.toList()) {
      if (key.startsWith('position|') || currentKeys.contains(key)) continue;
      final sep = key.indexOf('|');
      out.add({'kind': key.substring(0, sep), 'id': key.substring(sep + 1), 'updated_at': now, 'deleted': true});
      pushed.remove(key);
    }
    for (var i = 0; i < out.length; i += 500) {
      await _api.pushSync(out.sublist(i, i + 500 > out.length ? out.length : i + 500));
    }
    await store.saveDoc('sync', {...syncDoc, 'cursor': cursor, 'pushed': pushed});
  }

  List<Map<String, dynamic>> _pendingPositions = const [];

  /// Reading positions: the most recent read on any device wins.
  Future<void> syncPositions() async {
    final library = ref.read(libraryProvider.notifier);
    for (final p in _pendingPositions) {
      final book = library.byId(p['id'] as String);
      final data = p['data'] as Map<String, dynamic>?;
      if (book == null || data == null) continue;
      final remoteAt = DateTime.fromMillisecondsSinceEpoch(p['updated_at'] as int);
      if (book.lastReadAt == null || remoteAt.isAfter(book.lastReadAt!)) {
        library.updatePosition(
          book.id,
          sid: data['sid'] as String,
          offset: ((data['offset'] as num?) ?? 0).toInt(),
          progress: (data['progress'] as num).toDouble(),
          at: remoteAt,
        );
      }
    }
    _pendingPositions = const [];
    final store = ref.read(storeProvider);
    final syncDoc = Map<String, dynamic>.from(store.doc('sync') ?? const {});
    final pushedAt = Map<String, int>.from((syncDoc['positions'] as Map?) ?? const {});
    final out = <Map<String, dynamic>>[];
    for (final b in ref.read(libraryProvider)) {
      final at = b.lastReadAt?.millisecondsSinceEpoch;
      if (at == null || b.positionSid == null || (pushedAt[b.id] ?? 0) >= at) continue;
      out.add({
        'kind': 'position',
        'id': b.id,
        'updated_at': at,
        'deleted': false,
        'data': {'sid': b.positionSid, if (b.positionOffset > 0) 'offset': b.positionOffset, 'progress': b.progress},
      });
      pushedAt[b.id] = at;
    }
    if (out.isNotEmpty) await _api.pushSync(out);
    await store.saveDoc('sync', {...syncDoc, 'positions': pushedAt});
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref);
  ref.onDispose(s.stop);
  return s;
});

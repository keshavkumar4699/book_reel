import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the Cloro server's sync/activity/social API,
/// following server/src/social/sync.ts (last write wins, tombstones, cursor).
class FakeServer {
  final Map<String, Map<String, Map<String, dynamic>>> items = {}; // user -> key -> item
  int seq = 0;
  final List<Map<String, dynamic>> activity = [];
  final Map<String, Map<String, dynamic>> profiles = {};

  /// Usernames that belong to someone else (PUT /v1/me/profile answers 409).
  final Set<String> takenHandles = {};
  final List<Map<String, dynamic>> shares = [];
  final List<String> kudos = [];

  /// The Today feed, newest first (GET /v1/feed pages through it 20 at a time).
  late final List<Map<String, dynamic>> feed = [
    {
      'id': 'f1',
      'userId': 'device:ravi',
      'type': 'session',
      'text': 'Ravi read Walden',
      'at': DateTime.now().subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
      'data': {
        'book': {'title': 'Walden', 'author': 'Henry David Thoreau'},
        'minutes': 34,
        'cards': 21,
        'progress': 0.41,
        'mood': 'calm',
        'quote': 'I went to the woods because I wished to live deliberately.',
      },
      'author': {'name': 'Ravi', 'handle': 'ravi', 'avatar': '🦊'},
      'kudos': 2,
      'gaveKudos': false,
      'comments': 1,
      'mine': false,
    },
    {
      'id': 'f2',
      'userId': 'device:ravi',
      'type': 'book_finished',
      'text': 'Ravi finished Walden 📚',
      'at': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
      'data': <String, dynamic>{},
      'author': {'name': 'Ravi', 'handle': 'ravi', 'avatar': '🦊'},
      'kudos': 0,
      'gaveKudos': false,
      'comments': 0,
      'mine': false,
    },
  ];

  /// Sessions posted (by client_id: the latest upload wins).
  final Map<String, Map<String, dynamic>> sessions = {};

  /// Comments by activity id.
  final Map<String, List<Map<String, dynamic>>> comments = {
    'f1': [
      {'id': 'c1', 'user_id': 'device:meera', 'name': 'Meera', 'handle': 'meera.reads', 'avatar': '', 'text': 'Such a calm book.', 'at': DateTime.now().subtract(const Duration(minutes: 10)).toUtc().toIso8601String(), 'mine': false, 'can_delete': false},
    ],
  };

  /// Play purchase tokens the "server" accepts, by plan; verified plans by user.
  final Map<String, String> playTokens = {};
  final Map<String, String> entitled = {};
  bool billingEnforced = true;

  /// Texts sent to /v1/tts; [speechStatus] other than 200 makes it fail.
  final List<Map<String, dynamic>> speechRequests = [];
  int speechStatus = 200;

  /// Voice returned by /v1/book/profile; null makes the endpoint fail.
  String? profileVoice = 'suspense';
  final List<Map<String, dynamic>> profileRequests = [];
  int requests = 0;

  /// Other readers, by id. Ravi follows you; whom you follow is [following].
  final Map<String, Map<String, dynamic>> readers = {
    'device:ravi': {'user_id': 'device:ravi', 'display_name': 'Ravi', 'handle': 'ravi', 'avatar': '🦊', 'pronouns': 'he/him', 'bio': 'Slow reader, fast walker', 'genres': ['History'], 'reading': 'Walden', 'streak': {'current': 12, 'best': 30}},
    'device:meera': {'user_id': 'device:meera', 'display_name': 'Meera', 'handle': 'meera.reads', 'avatar': '', 'pronouns': '', 'bio': '', 'genres': <String>[], 'reading': '', 'streak': {'current': 0, 'best': 4}},
  };
  final Set<String> followers = {'device:ravi'};
  final Set<String> following = {};

  MockClient get client => MockClient((req) async {
        requests++;
        final user = req.headers['x-device-id']!;
        final path = req.url.path;
        Map<String, dynamic> body() => jsonDecode(req.body) as Map<String, dynamic>;
        final seg = req.url.pathSegments;
        http.Response ok(Object o) =>
            http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        if (path == '/v1/sync' && req.method == 'PUT') {
          var applied = 0;
          final mine = items.putIfAbsent(user, () => {});
          for (final i in (body()['items'] as List).cast<Map<String, dynamic>>()) {
            final key = '${i['kind']}|${i['id']}';
            final existing = mine[key];
            if (existing != null && (existing['updated_at'] as int) >= (i['updated_at'] as int)) continue;
            mine[key] = {...i, 'seq': ++seq};
            applied++;
          }
          return ok({'applied': applied, 'cursor': seq});
        }
        if (path == '/v1/sync' && req.method == 'GET') {
          final since = int.parse(req.url.queryParameters['since'] ?? '0');
          final list = (items[user]?.values ?? const <Map<String, dynamic>>[]).where((i) => (i['seq'] as int) > since).toList()
            ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
          return ok({
            'items': [for (final i in list) {...i}..remove('seq')],
            'cursor': list.isEmpty ? since : list.last['seq'],
            'more': false,
          });
        }
        if (path == '/v1/activity/batch') {
          final events = (body()['events'] as List).cast<Map<String, dynamic>>();
          activity.addAll(events);
          return ok({'accepted': events.length, 'verified': events.length, 'streak': 1, 'wpm': 230});
        }
        if (path == '/v1/billing/verify') {
          final b = body();
          final tier = playTokens[b['purchase_token']];
          if (tier == null) return http.Response('{"error":"invalid_purchase"}', 400);
          entitled[user] = tier;
          return ok({'tier': tier, 'product_id': b['product_id'], 'expires_at': '2027-01-01T00:00:00.000Z', 'enforced': billingEnforced});
        }
        if (path == '/v1/billing/entitlement') {
          return ok({'tier': entitled[user] ?? 'free', 'expires_at': null, 'enforced': billingEnforced});
        }
        if (path == '/v1/tts') {
          if (speechStatus != 200) return http.Response('{"error":"tts_unavailable"}', speechStatus);
          final b = body();
          speechRequests.add(b);
          return http.Response.bytes(utf8.encode('ID3 mp3 ${b['voice']} ${b['text']}'), 200, headers: {'content-type': 'audio/mpeg'});
        }
        if (path == '/v1/me/profile') {
          final b = body();
          if (takenHandles.contains(b['handle'])) return http.Response('{"error":"handle_taken"}', 409);
          profiles[user] = {...?profiles[user], ...b};
          return ok(profiles[user]!);
        }
        if (path == '/v1/me') {
          return ok({
            'user_id': 'device:$user',
            'display_name': 'Asha',
            'invite_code': '7PA756JQ',
            'invite_url': 'https://bookreel.app/i/7PA756JQ',
            'signed_in': false,
            'followers': followers.length,
            'following': following.length,
          });
        }
        Map<String, dynamic> person(String id) => {
              for (final k in ['user_id', 'display_name', 'handle', 'avatar']) k: readers[id]![k],
              'you_follow': following.contains(id),
            };
        String? byHandle(String h) {
          final r = readers.values.where((r) => r['handle'] == h.replaceFirst('@', '').toLowerCase()).firstOrNull;
          return r == null ? null : r['user_id'] as String;
        }

        if (seg.length >= 3 && seg[0] == 'v1' && seg[1] == 'users') {
          final String? id;
          if (seg[2] == 'me' || seg[2] == 'device:$user') {
            id = 'me';
          } else if (seg[2].startsWith('@')) {
            id = byHandle(seg[2]);
          } else {
            id = readers.containsKey(seg[2]) ? seg[2] : null;
          }
          if (id == null) return http.Response('{"error":"not_found"}', 404);
          if (seg.length == 4) {
            final ids = id != 'me' ? <String>[] : (seg[3] == 'followers' ? followers : following).toList();
            return ok({'items': [for (final i in ids) person(i)]});
          }
          if (id == 'me') return ok({'user_id': 'device:$user', 'display_name': 'Asha', 'me': true, 'followers': followers.length, 'following': following.length});
          return ok({
            ...readers[id]!,
            'followers': following.contains(id) ? 1 : 0,
            'following': followers.contains(id) ? 1 : 0,
            'you_follow': following.contains(id),
            'follows_you': followers.contains(id),
            'me': false,
          });
        }
        if (path == '/v1/social/follow-handle') {
          final id = byHandle(body()['handle'] as String);
          if (id == null) return http.Response('{"error":"not_found"}', 404);
          following.add(id);
          return ok({'user': person(id)});
        }
        if (seg.length == 4 && seg[1] == 'social' && seg[2] == 'follow') {
          if (!readers.containsKey(seg[3])) return http.Response('{"error":"not_found"}', 404);
          req.method == 'DELETE' ? following.remove(seg[3]) : following.add(seg[3]);
          return ok({'ok': true});
        }
        if (path == '/v1/leagues/current') {
          return ok({
            'division': 'Silver',
            'promote': 5,
            'demote': 5,
            'rows': [
              {'userId': 'x', 'name': 'Ravi', 'me': false, 'activeDays': 4, 'minutes': 80, 'score': 4080, 'rank': 1},
              {'userId': 'device:$user', 'name': 'Asha', 'me': true, 'activeDays': 3, 'minutes': 50, 'score': 3050, 'rank': 2},
            ],
          });
        }
        if (path == '/v1/leaderboards/friends') {
          return ok({'rows': [
            {'userId': 'device:$user', 'name': 'Asha', 'me': true, 'activeDays': 3, 'minutes': 50, 'score': 3050},
          ]});
        }
        if (path == '/v1/feed') {
          final before = DateTime.tryParse(req.url.queryParameters['before'] ?? '');
          final list = [
            for (final f in feed)
              if (before == null || DateTime.parse(f['at'] as String).isBefore(before)) f,
          ];
          return ok({'items': list.take(20).toList()});
        }
        if (path == '/v1/activities/session') {
          final b = body();
          sessions[b['client_id'] as String] = b;
          return ok({'id': 'srv-${b['client_id']}'});
        }
        if (path.startsWith('/v1/activities/') && path.endsWith('/kudos')) {
          kudos.add(path.split('/')[3]);
          return ok({'ok': true});
        }
        if (seg.length == 4 && seg[1] == 'activities' && seg[3] == 'comments') {
          final list = comments.putIfAbsent(seg[2], () => []);
          if (req.method == 'POST') {
            final c = {
              'id': 'c${list.length + 100}',
              'user_id': 'device:$user',
              'name': 'Asha',
              'handle': null,
              'avatar': '',
              'text': body()['text'],
              'at': DateTime.now().toUtc().toIso8601String(),
              'mine': true,
              'can_delete': true,
            };
            list.add(c);
            return ok({'comment': c});
          }
          return ok({'items': list});
        }
        if (seg.length == 3 && seg[1] == 'comments' && req.method == 'DELETE') {
          for (final list in comments.values) {
            list.removeWhere((c) => c['id'] == seg[2]);
          }
          return ok({'ok': true});
        }
        if (path == '/v1/book/profile') {
          final b = body();
          if (b['tier'] == 'free') return http.Response('{"error":"tier_not_eligible"}', 403);
          profileRequests.add(b);
          if (profileVoice == null) return http.Response('{"error":"down"}', 500);
          return ok({'voice': profileVoice, 'genre': 'test genre', 'source': 'ai'});
        }
        if (path == '/v1/share') {
          shares.add(body());
          return ok({'id': 'abc', 'url': 'https://bookreel.app/c/abc'});
        }
        return http.Response('{"error":"not found"}', 404);
      });
}

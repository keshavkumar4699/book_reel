import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the BookReel server's sync/activity/social API,
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

  MockClient get client => MockClient((req) async {
        requests++;
        final user = req.headers['x-device-id']!;
        final path = req.url.path;
        Map<String, dynamic> body() => jsonDecode(req.body) as Map<String, dynamic>;
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
          return ok({'user_id': 'device:$user', 'display_name': 'Asha', 'invite_code': '7PA756JQ', 'invite_url': 'https://bookreel.app/i/7PA756JQ', 'signed_in': false});
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
          return ok({'items': [
            {'id': 'f1', 'userId': 'x', 'type': 'book_finished', 'text': 'Ravi finished Walden 📚', 'at': DateTime.now().toUtc().toIso8601String(), 'kudos': 2, 'gaveKudos': false, 'mine': false},
          ]});
        }
        if (path.startsWith('/v1/activities/') && path.endsWith('/kudos')) {
          kudos.add(path.split('/')[3]);
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

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
  final List<Map<String, dynamic>> shares = [];
  final List<String> kudos = [];
  List<Map<String, dynamic>> musicTracks = [];
  Map<String, String> planPicks = {};
  bool failMusicPlan = false;
  int musicPlanRequests = 0;
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
        if (path == '/v1/me/profile') {
          profiles[user] = body();
          return ok(body());
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
        if (path == '/v1/music/tracks') {
          if (req.url.queryParameters['tier'] == 'free') return http.Response('{"error":"tier_not_eligible"}', 403);
          return ok({'tracks': musicTracks});
        }
        if (path == '/v1/music/plan') {
          if (failMusicPlan) return http.Response('{"error":"down"}', 500);
          final cues = (body()['cues'] as List).cast<Map<String, dynamic>>();
          musicPlanRequests++;
          return ok({
            'picks': [for (final c in cues) {'at_card': c['at_card'], 'track_id': planPicks[c['mood']] ?? 'missing'}],
            'source': 'ai',
          });
        }
        if (path == '/v1/share') {
          shares.add(body());
          return ok({'id': 'abc', 'url': 'https://bookreel.app/c/abc'});
        }
        return http.Response('{"error":"not found"}', 404);
      });
}

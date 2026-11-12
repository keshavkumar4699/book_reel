import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'ai_client.dart' show bookreelApi;
import 'segments.dart' show deviceIdProvider;

class ApiException implements Exception {
  ApiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'API error $status: $body';
}

/// Client for the BookReel server's account, activity, social, sync and share
/// endpoints (server/src/app.ts). Callers are identified by device ID until
/// Google sign-in is configured (IMPLEMENTATION_PLAN.md Phase 7).
class BookReelApi {
  BookReelApi({required this.baseUrl, required this.deviceId, http.Client? httpClient, DateTime Function()? clock})
      : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final String baseUrl;
  final String deviceId;
  final http.Client _http;
  final DateTime Function() _clock;

  bool get enabled => baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-device-id': deviceId,
        'x-tz-offset': '${_clock().timeZoneOffset.inMinutes}',
      };

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    // JSON is always UTF-8; don't rely on the response declaring a charset.
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode >= 400) throw ApiException(res.statusCode, text);
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<Map<String, dynamic>> me() async => (await _send('GET', '/v1/me')) as Map<String, dynamic>;

  /// Natural read-aloud audio (MP3) for [text]. Throws [ApiException] 503
  /// when the server has no voice provider, 429 over the daily allowance.
  Future<Uint8List> speech({required String text, required String voice, required double speed, required String tier}) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/v1/tts'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'text': text, 'voice': voice, 'speed': speed, 'tier': tier});
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
    return res.bodyBytes;
  }

  /// Updates the server's copy of the profile. Throws [ApiException] 409
  /// when [handle] belongs to someone else.
  Future<void> updateProfile({
    String? displayName,
    int? dailyGoalCards,
    int? freezesPerWeek,
    String? handle,
    String? pronouns,
    String? bio,
    String? avatar,
  }) =>
      _send('PUT', '/v1/me/profile', {
        'display_name': ?displayName,
        'daily_goal_cards': ?dailyGoalCards,
        'freezes_per_week': ?freezesPerWeek,
        'handle': ?handle,
        'pronouns': ?pronouns,
        'bio': ?bio,
        'avatar': ?avatar,
      });

  Future<Map<String, dynamic>> uploadActivity(List<Map<String, dynamic>> events) async =>
      (await _send('POST', '/v1/activity/batch', {'tz_offset_min': _clock().timeZoneOffset.inMinutes, 'events': events}))
          as Map<String, dynamic>;

  Future<void> bookFinished(String title) => _send('POST', '/v1/activity/book-finished', {'title': title});

  Future<Map<String, dynamic>?> league() async {
    try {
      return (await _send('GET', '/v1/leagues/current')) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> friendsBoard() async =>
      (((await _send('GET', '/v1/leaderboards/friends')) as Map<String, dynamic>)['rows'] as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> feed() async =>
      (((await _send('GET', '/v1/feed')) as Map<String, dynamic>)['items'] as List).cast<Map<String, dynamic>>();

  Future<void> kudos(String activityId) => _send('POST', '/v1/activities/$activityId/kudos');

  /// Adds a friend by invite code; returns their name, or null for an unknown code.
  Future<String?> addFriend(String code) async {
    try {
      final res = (await _send('POST', '/v1/social/follow-code', {'code': code})) as Map<String, dynamic>;
      return (res['friend'] as Map<String, dynamic>)['name'] as String;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> removeFriend(String userId) => _send('DELETE', '/v1/social/follow/${Uri.encodeComponent(userId)}');

  Future<Map<String, dynamic>> pushSync(List<Map<String, dynamic>> items) async =>
      (await _send('PUT', '/v1/sync', {'items': items})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> pullSync(int since) async => (await _send('GET', '/v1/sync?since=$since')) as Map<String, dynamic>;

  /// Asks the AI which typographic voice fits a book (paid tiers); returns
  /// the voice name. Only metadata and a short opening sample are sent.
  Future<String> bookProfile(
    String tier, {
    required String title,
    required String author,
    required String contentHash,
    List<String> subjects = const [],
    required String sample,
  }) async {
    final res = (await _send('POST', '/v1/book/profile', {
      'tier': tier,
      'book': {'title': title, 'author': author, 'content_hash': contentHash},
      'subjects': subjects.take(12).toList(),
      'sample': sample.length > 6000 ? sample.substring(0, 6000) : sample,
    })) as Map<String, dynamic>;
    return res['voice'] as String;
  }

  /// Creates a short share link with a web preview; returns its URL.
  Future<String> createShare(Map<String, dynamic> payload) async =>
      ((await _send('POST', '/v1/share', payload)) as Map<String, dynamic>)['url'] as String;
}

final apiProvider = Provider<BookReelApi>((ref) => BookReelApi(baseUrl: bookreelApi, deviceId: ref.read(deviceIdProvider)));

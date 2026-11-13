import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Calm notifications (UX_DESIGN.md §5.10): at most one daily reminder at the
/// user's chosen time, worded with their habit anchor, plus a gentle
/// streak nudge at 20:00 only when today's goal isn't met. Nothing during
/// quiet hours (22:00–08:00).
class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  static const _dailyId = 1;
  static const _nudgeId = 2;
  static const quietStartHour = 22;
  static const quietEndHour = 8;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reading_reminders',
      'Reading reminders',
      channelDescription: 'One gentle daily reminder to read',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static bool isQuietHour(int hour) => hour >= quietStartHour || hour < quietEndHour;

  /// Text for the daily reminder, using the user's own words when given.
  static String reminderBody({required String habitAnchor, required int dailyGoal, String? bookTitle}) {
    final what = bookTitle == null ? '$dailyGoal cards' : '$dailyGoal cards of $bookTitle';
    final anchor = habitAnchor.trim();
    return anchor.isEmpty ? 'Time for $what?' : '$anchor: $what?';
  }

  Future<void> scheduleDaily({
    required bool enabled,
    required int hour,
    required int minute,
    required String body,
  }) async {
    if (!_ready) return;
    await _plugin.cancel(id: _dailyId);
    if (!enabled || isQuietHour(hour)) return;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _dailyId,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Cloro',
      body: body,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedules today's 20:00 streak nudge (call when the app goes to the
  /// background with the goal unmet); cancelled once the goal is met.
  Future<void> scheduleStreakNudge({required int streak, required int freezesLeft}) async {
    if (!_ready || streak <= 0) return;
    final now = tz.TZDateTime.now(tz.local);
    final at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    if (!at.isAfter(now)) return;
    final body = freezesLeft > 0
        ? 'Your $streak-day streak is safe with a freeze, or read 3 cards to keep it going.'
        : 'Keep your $streak-day streak going? A few cards is enough.';
    await _plugin.zonedSchedule(
      id: _nudgeId,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Cloro',
      body: body,
    );
  }

  Future<void> cancelStreakNudge() async {
    if (_ready) await _plugin.cancel(id: _nudgeId);
  }
}

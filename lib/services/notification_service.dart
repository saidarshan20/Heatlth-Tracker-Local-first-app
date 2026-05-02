// ignore_for_file: avoid_print
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'database_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _isRescheduling = false;
  static DateTime? _lastReschedule;

  // Reserved ID for the live fasting notification
  static const int fastingNotificationId = 8888;

  static Future<void> init() async {
    if (_initialized) return;

    // Initialize timezone database and set local timezone
    tzdata.initializeTimeZones();
    final deviceTzInfo = await FlutterTimezone.getLocalTimezone();
    final deviceTz = deviceTzInfo.toString();
    try {
      tz.setLocalLocation(tz.getLocation(deviceTz));
      print('Timezone set to: $deviceTz');
    } catch (_) {
      // Fallback to Asia/Kolkata if timezone not found
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      print('Timezone fallback to Asia/Kolkata');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  static Future<bool> checkPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final enabled = await android.areNotificationsEnabled();
    return enabled ?? false;
  }

  static Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    print('Scheduling notification #$id "$title" at $scheduled (local: ${tz.local.name})');

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_reminders',
          'Health Tracker Reminders',
          channelDescription: 'Medicine, water, and meal reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Like [scheduleDailyNotification] but always starts from tomorrow.
  /// Use this after a medicine is marked as taken so today's alarm is skipped.
  static Future<void> scheduleDailyNotificationFromTomorrow({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    // Force tomorrow regardless of current time
    final tomorrow = now.add(const Duration(days: 1));
    final scheduled = tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, hour, minute);

    print('Scheduling (tomorrow) notification #$id "$title" at $scheduled');

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_reminders',
          'Health Tracker Reminders',
          channelDescription: 'Medicine, water, and meal reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      // NO matchDateTimeComponents — this is a one-shot for tomorrow only.
      // The next rescheduleAll() (on app startup or midnight rollover) will
      // re-create the daily-repeating alarm via scheduleDailyNotification().
    );
  }

  /// Send an immediate test notification
  static Future<void> sendTestNotification() async {
    await _plugin.show(
      id: 9999,
      title: '🔔 Test Notification',
      body: 'Notifications are working! You\'ll get your reminders on time.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_reminders',
          'Health Tracker Reminders',
          channelDescription: 'Medicine, water, and meal reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  static Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id: id);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Shows (or updates) a persistent live-fasting notification.
  /// Call this once when a fast starts, and again every minute to refresh the timer.
  static Future<void> showFastingNotification(DateTime startTime) async {
    final elapsed = DateTime.now().difference(startTime);
    final goalMinutes = 16 * 60;
    final remaining = Duration(minutes: (goalMinutes - elapsed.inMinutes).clamp(0, goalMinutes));
    final progress = (elapsed.inMinutes / goalMinutes).clamp(0.0, 1.0);

    final elapsedStr =
        '${elapsed.inHours}h ${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}m';
    final remainingStr = elapsed.inMinutes >= goalMinutes
        ? '🎉 Goal reached!'
        : '${remaining.inHours}h ${(remaining.inMinutes % 60).toString().padLeft(2, '0')}m left';

    // Build a simple ASCII progress bar (10 chars)
    final filled = (progress * 10).round();
    final bar = '${'█' * filled}${'░' * (10 - filled)}';

    await _plugin.show(
      id: fastingNotificationId,
      title: '⚡ Fasting — $elapsedStr elapsed',
      body: '$bar  $remainingStr',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_fasting',
          'Fasting Tracker',
          channelDescription: 'Live fasting progress notification',
          importance: Importance.low,      // low = silent, no heads-up popup
          priority: Priority.low,
          icon: '@mipmap/launcher_icon',
          ongoing: true,                  // can't be swiped away
          autoCancel: false,
          showWhen: true,                 // required for chronometer
          when: startTime.millisecondsSinceEpoch,
          usesChronometer: true,          // native OS background ticking
          onlyAlertOnce: true,            // don't buzz on every update
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  /// Cancels the live fasting notification when the fast ends.
  static Future<void> cancelFastingNotification() async {
    await _plugin.cancel(id: fastingNotificationId);
  }

  // ── Sleep Tracker Notification ──
  static const int sleepNotificationId = 8999;

  /// Shows (or updates) a persistent live-sleep notification.
  /// Call this once when sleep starts, and again periodically to refresh the timer.
  static Future<void> showSleepNotification(DateTime startTime) async {
    final elapsed = DateTime.now().difference(startTime);
    final goalMinutes = 8 * 60;
    final remaining = Duration(minutes: (goalMinutes - elapsed.inMinutes).clamp(0, goalMinutes));
    final progress = (elapsed.inMinutes / goalMinutes).clamp(0.0, 1.0);

    final elapsedStr =
        '${elapsed.inHours}h ${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}m';
    final remainingStr = elapsed.inMinutes >= goalMinutes
        ? '🎉 8h goal reached!'
        : '${remaining.inHours}h ${(remaining.inMinutes % 60).toString().padLeft(2, '0')}m left';

    // Build a simple ASCII progress bar (10 chars)
    final filled = (progress * 10).round();
    final bar = '${'█' * filled}${'░' * (10 - filled)}';

    await _plugin.show(
      id: sleepNotificationId,
      title: '😴 Sleeping — $elapsedStr',
      body: '$bar  $remainingStr',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_sleep',
          'Sleep Tracker',
          channelDescription: 'Live sleep progress notification',
          importance: Importance.low,
          priority: Priority.low,
          icon: '@mipmap/launcher_icon',
          ongoing: true,
          autoCancel: false,
          showWhen: true,                 // required for chronometer
          when: startTime.millisecondsSinceEpoch,
          usesChronometer: true,          // native OS background ticking
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  /// Cancels the live sleep notification when sleep ends.
  static Future<void> cancelSleepNotification() async {
    await _plugin.cancel(id: sleepNotificationId);
  }

  // Reserved ID for the weekly weight reminder
  static const int weightReminderNotifId = 9000;

  /// Schedules a weekly weight-logging reminder on [weekday] (1=Mon, 7=Sun)
  /// at [hour]:[minute]. Repeats every week automatically.
  static Future<void> scheduleWeeklyWeightReminder({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    var dt = tz.TZDateTime.now(tz.local);
    dt = tz.TZDateTime(tz.local, dt.year, dt.month, dt.day, hour, minute);
    // Advance until we land on the right weekday AND the time is in the future
    for (int i = 0; i < 8; i++) {
      if (dt.weekday == weekday && dt.isAfter(tz.TZDateTime.now(tz.local))) break;
      dt = dt.add(const Duration(days: 1));
    }
    print('Scheduling weekly weight reminder: weekday=$weekday at $dt');
    await _plugin.zonedSchedule(
      id: weightReminderNotifId,
      title: '⚖️ Weigh-in day!',
      body: "Don't forget to log your weight — track your progress!",
      scheduledDate: dt,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_weight',
          'Weight Reminders',
          channelDescription: 'Weekly weight logging reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> cancelWeightReminder() async {
    await _plugin.cancel(id: weightReminderNotifId);
  }

  // Reserved ID for daily summary notification
  static const int summaryNotifId = 9001;

  /// Schedules (or reschedules) the daily summary notification.
  /// Reads config from DB: summary_enabled, summary_hour, summary_minute.
  static Future<void> scheduleDailySummaryIfEnabled() async {
    final enabled = await DatabaseService.getSettingBool('summary_enabled', false);
    if (!enabled) {
      await _plugin.cancel(id: summaryNotifId);
      return;
    }

    final hour = await DatabaseService.getSettingInt('summary_hour', 9);
    final minute = await DatabaseService.getSettingInt('summary_minute', 0);

    // Build yesterday's summary
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    final foodTotals = await DatabaseService.getFoodTotals(yStr);
    final waterTotal = await DatabaseService.getWaterTotal(yStr);
    final cal = foodTotals['cal'] ?? 0;
    final prot = foodTotals['p'] ?? 0;
    final waterL = (waterTotal / 1000).toStringAsFixed(1);

    String body = '🔥 $cal kcal · P:${prot}g · 💧 ${waterL}L';

    // Check for fasting yesterday
    final db = await DatabaseService.database;
    final fastRows = await db.rawQuery(
      "SELECT SUM(COALESCE(duration_min, 0)) as total FROM fasting_logs WHERE DATE(start_time) = ?",
      [yStr],
    );
    final fastMin = (fastRows.first['total'] as num?)?.toInt() ?? 0;
    if (fastMin > 0) {
      body += ' · ⚡ ${fastMin ~/ 60}h${fastMin % 60 > 0 ? ' ${fastMin % 60}m' : ''} fast';
    }

    // Check for sleep yesterday
    final sleepRows = await db.rawQuery(
      "SELECT duration_min FROM sleep_logs WHERE DATE(start_time) = ? AND end_time IS NOT NULL ORDER BY id DESC LIMIT 1",
      [yStr],
    );
    if (sleepRows.isNotEmpty) {
      final sleepMin = (sleepRows.first['duration_min'] as num?)?.toInt() ?? 0;
      if (sleepMin > 0) {
        body += ' · 😴 ${sleepMin ~/ 60}h${sleepMin % 60 > 0 ? ' ${sleepMin % 60}m' : ''}';
      }
    }

    await scheduleDailyNotification(
      id: summaryNotifId,
      title: '📋 Yesterday\'s Summary',
      body: body,
      hour: hour,
      minute: minute,
    );
    print('Scheduled daily summary at $hour:${minute.toString().padLeft(2, '0')}');
  }

  static Future<void> cancelSummaryNotification() async {
    await _plugin.cancel(id: summaryNotifId);
  }

  static const int _waterSuppressionWindowMinutes = 20;

  /// After logging water, cancel any water reminder scheduled to fire within
  /// the next [_waterSuppressionWindowMinutes] minutes and reschedule from tomorrow.
  static Future<void> suppressUpcomingWaterReminder() async {
    final reminders = await DatabaseService.getReminders(type: 'water');
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;
    final windowEnd = nowMins + _waterSuppressionWindowMinutes;

    for (final r in reminders) {
      if ((r['active'] as int) != 1) continue;
      final rMins = (r['hour'] as int) * 60 + (r['minute'] as int);

      // Midnight-safe window check
      final inWindow = windowEnd <= 1440
          ? (rMins >= nowMins && rMins <= windowEnd)
          : (rMins >= nowMins || rMins <= windowEnd % 1440);
      if (!inWindow) continue;

      final notifId = 2000 + (r['id'] as int);
      await cancelNotification(notifId);
      await scheduleDailyNotificationFromTomorrow(
        id: notifId,
        title: '💧 Water Reminder',
        body: (r['label'] as String).isNotEmpty ? r['label'] as String : 'Time to drink some water!',
        hour: r['hour'] as int,
        minute: r['minute'] as int,
      );
      // Persist suppression so rescheduleAll() respects it across app restarts
      await DatabaseService.suppressNotifForToday(notifId);
      print('Suppressed water reminder #$notifId — water just logged');
    }
  }

  /// After logging food with a meal keyword (breakfast/lunch/dinner), cancel the
  /// matching meal reminder for today and reschedule from tomorrow.
  static Future<void> suppressMealReminderIfKeyword(String foodItem, {String? rawInput}) async {
    // Check both the AI-processed name and the user's original input for keywords
    final itemLower = foodItem.toLowerCase();
    final rawLower = rawInput?.toLowerCase() ?? '';
    final keywords = <String>[];
    if (itemLower.contains('breakfast') || rawLower.contains('breakfast')) keywords.add('breakfast');
    if (itemLower.contains('lunch') || rawLower.contains('lunch')) keywords.add('lunch');
    if (itemLower.contains('dinner') || rawLower.contains('dinner')) keywords.add('dinner');
    if (keywords.isEmpty) return;

    // Skip scheduling-from-tomorrow if a fast is active — rescheduleAll handles resumption on fast end
    final activeFast = await DatabaseService.getActiveFast();

    final reminders = await DatabaseService.getReminders(type: 'meal');
    for (final r in reminders) {
      if ((r['active'] as int) != 1) continue;
      if (!keywords.any((kw) => (r['label'] as String).toLowerCase().contains(kw))) continue;

      final notifId = 3000 + (r['id'] as int);
      await cancelNotification(notifId);
      if (activeFast == null) {
        await scheduleDailyNotificationFromTomorrow(
          id: notifId,
          title: '🍽️ Meal Reminder',
          body: r['label'] as String,
          hour: r['hour'] as int,
          minute: r['minute'] as int,
        );
      }
      // Persist suppression so rescheduleAll() respects it across app restarts
      await DatabaseService.suppressNotifForToday(notifId);
      print('Suppressed meal reminder #$notifId — "$foodItem" logged');
    }
  }

  /// Reschedule all reminders from the database
  static Future<void> rescheduleAll({bool force = false}) async {
    if (_isRescheduling) return;
    
    final now = DateTime.now();
    if (!force && _lastReschedule != null && now.difference(_lastReschedule!).inSeconds < 5) {
      print('rescheduleAll debounced');
      return;
    }
    
    _isRescheduling = true;
    _lastReschedule = now;
    
    try {
      await cancelAll(); // Clean slate to avoid duplicates or orphaned alarms

      // Remove stale suppression rows from previous days
      await DatabaseService.clearExpiredSuppressions();

      // Schedule medicine reminders
      final medicines = await DatabaseService.getMedicines();
      for (final med in medicines) {
        final parts = (med['reminder_time'] as String).split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 9;
          final minute = int.tryParse(parts[1]) ?? 0;
          final medId = 1000 + (med['id'] as int);
          final suppressed = await DatabaseService.isNotifSuppressedToday(medId);
          if (suppressed) {
            await scheduleDailyNotificationFromTomorrow(
              id: medId,
              title: '💊 Medicine Reminder',
              body: 'Time to take ${med['name']}',
              hour: hour,
              minute: minute,
            );
          } else {
            await scheduleDailyNotification(
              id: medId,
              title: '💊 Medicine Reminder',
              body: 'Time to take ${med['name']}',
              hour: hour,
              minute: minute,
            );
          }
        }
      }

      // Skip meal reminders while a fast is active
      final activeFast = await DatabaseService.getActiveFast();
      final fastIsActive = activeFast != null;

      // Schedule water & meal reminders
      final reminders = await DatabaseService.getReminders();
      for (final r in reminders) {
        if ((r['active'] as int) != 1) continue;
        final id = r['id'] as int;
        final type = r['type'] as String;
        final label = r['label'] as String;
        final hour = r['hour'] as int;
        final minute = r['minute'] as int;

        if (type == 'water') {
          final waterId = 2000 + id;
          final waterSuppressed = await DatabaseService.isNotifSuppressedToday(waterId);
          if (waterSuppressed) {
            await scheduleDailyNotificationFromTomorrow(
              id: waterId,
              title: '💧 Water Reminder',
              body: label.isNotEmpty ? label : 'Time to drink some water!',
              hour: hour,
              minute: minute,
            );
          } else {
            await scheduleDailyNotification(
              id: waterId,
              title: '💧 Water Reminder',
              body: label.isNotEmpty ? label : 'Time to drink some water!',
              hour: hour,
              minute: minute,
            );
          }
        } else if (type == 'meal') {
          if (fastIsActive) continue;
          final mealId = 3000 + id;
          final mealSuppressed = await DatabaseService.isNotifSuppressedToday(mealId);
          if (mealSuppressed) {
            await scheduleDailyNotificationFromTomorrow(
              id: mealId,
              title: '🍽️ Meal Reminder',
              body: label.isNotEmpty ? label : 'Time to log your meal!',
              hour: hour,
              minute: minute,
            );
          } else {
            await scheduleDailyNotification(
              id: mealId,
              title: '🍽️ Meal Reminder',
              body: label.isNotEmpty ? label : 'Time to log your meal!',
              hour: hour,
              minute: minute,
            );
          }
        }
      }

      // Schedule daily summary notification if enabled
      await scheduleDailySummaryIfEnabled();

      print('Rescheduled ${medicines.length} medicine + ${reminders.where((r) => (r['active'] as int) == 1).length} other reminders');
    } finally {
      _isRescheduling = false;
    }
  }
}

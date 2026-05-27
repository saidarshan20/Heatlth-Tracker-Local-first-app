// ignore_for_file: avoid_print
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'database_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  // Native AlarmManager bridge — used for ALL scheduled reminders. The
  // flutter_local_notifications plugin remains only for live chronometer-style
  // notifications (fasting, sleep). See android/app/.../AlarmScheduler.kt.
  static const _alarmChannel = MethodChannel('health_tracker/alarms');
  static bool _initialized = false;
  static bool _isRescheduling = false;
  static DateTime? _lastReschedule;

  static const int fastingNotificationId = 8888;
  static const int sleepReminderNotifId = 9002;

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

  /// Schedules a daily-repeating reminder via the native AlarmManager bridge.
  /// Fires once at the next hour:minute (today if not yet passed, else
  /// tomorrow), and the native receiver re-arms it for +24h after each fire.
  static Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    print('Scheduling notification #$id "$title" at $hour:${minute.toString().padLeft(2, '0')} (native)');
    try {
      await _alarmChannel.invokeMethod('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'hour': hour,
        'minute': minute,
        'fromTomorrow': false,
      });
    } on PlatformException catch (e) {
      print('Alarm schedule failed #$id: ${e.code} ${e.message}');
    }
  }

  /// Like [scheduleDailyNotification] but always starts from tomorrow.
  /// Use this after a medicine/water/meal is marked done so today's alarm is skipped.
  static Future<void> scheduleDailyNotificationFromTomorrow({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    print('Scheduling (tomorrow) notification #$id "$title" at $hour:${minute.toString().padLeft(2, '0')} (native)');
    try {
      await _alarmChannel.invokeMethod('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'hour': hour,
        'minute': minute,
        'fromTomorrow': true,
      });
    } on PlatformException catch (e) {
      print('Alarm tomorrow-schedule failed #$id: ${e.code} ${e.message}');
    }
  }

  /// True if Android will allow exact alarms (Android 12+ permission gate).
  static Future<bool> canScheduleExactAlarms() async {
    try {
      final ok = await _alarmChannel.invokeMethod<bool>('canScheduleExact');
      return ok ?? true;
    } on PlatformException {
      return true;
    }
  }

  /// Opens the system "Allow exact alarms" settings page (Android 12+).
  static Future<void> requestExactAlarmPermission() async {
    try {
      await _alarmChannel.invokeMethod('requestExactPermission');
    } on PlatformException catch (e) {
      print('requestExactPermission failed: ${e.message}');
    }
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
    // Cancel both the posted notification (if any) and any pending native alarm.
    await _plugin.cancel(id: id);
    try {
      await _alarmChannel.invokeMethod('cancel', {'id': id});
    } on PlatformException catch (e) {
      print('Alarm cancel failed #$id: ${e.message}');
    }
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
    // Native alarms are id-scoped; rescheduleAll's per-id cancel handles them.
  }

  /// Native-only cancel — used inside rescheduleAll to clear AlarmManager
  /// pendings without also touching the flutter_local_notifications side.
  static Future<void> _cancelNative(int id) async {
    try {
      await _alarmChannel.invokeMethod('cancel', {'id': id});
    } on PlatformException catch (_) {/* ignore */}
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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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

  /// Schedules (or cancels) a daily sleep reminder notification.
  /// Skips today if a sleep session is already active or was suppressed
  /// (e.g. the user manually started sleep before the scheduled reminder).
  static Future<void> scheduleSleepReminderIfEnabled() async {
    final enabled = await DatabaseService.getSettingBool('sleep_reminder_enabled', false);
    if (!enabled) {
      await _plugin.cancel(id: sleepReminderNotifId);
      return;
    }
    final hour = await DatabaseService.getSettingInt('sleep_reminder_hour', 23);
    final minute = await DatabaseService.getSettingInt('sleep_reminder_minute', 0);

    // Skip today if user is already sleeping or has marked today as suppressed.
    final activeSleep = await DatabaseService.getActiveSleep();
    final suppressedToday = await DatabaseService.isNotifSuppressedToday(sleepReminderNotifId);
    if (activeSleep != null || suppressedToday) {
      await scheduleDailyNotificationFromTomorrow(
        id: sleepReminderNotifId,
        title: '🌙 Time to sleep!',
        body: 'Rest is as important as nutrition. Head to bed soon.',
        hour: hour,
        minute: minute,
      );
      print('Sleep reminder deferred to tomorrow (active=$activeSleep, suppressedToday=$suppressedToday)');
      return;
    }

    await scheduleDailyNotification(
      id: sleepReminderNotifId,
      title: '🌙 Time to sleep!',
      body: 'Rest is as important as nutrition. Head to bed soon.',
      hour: hour,
      minute: minute,
    );
    print('Scheduled sleep reminder at $hour:${minute.toString().padLeft(2, '0')}');
  }

  /// Called when the user manually starts a sleep session. Cancels today's
  /// sleep reminder and reschedules it from tomorrow so it doesn't fire while
  /// they're already in bed.
  static Future<void> suppressSleepReminderForToday() async {
    final enabled = await DatabaseService.getSettingBool('sleep_reminder_enabled', false);
    await cancelNotification(sleepReminderNotifId);
    await DatabaseService.suppressNotifForToday(sleepReminderNotifId);
    if (!enabled) return;
    final hour = await DatabaseService.getSettingInt('sleep_reminder_hour', 23);
    final minute = await DatabaseService.getSettingInt('sleep_reminder_minute', 0);
    await scheduleDailyNotificationFromTomorrow(
      id: sleepReminderNotifId,
      title: '🌙 Time to sleep!',
      body: 'Rest is as important as nutrition. Head to bed soon.',
      hour: hour,
      minute: minute,
    );
    print('Suppressed sleep reminder — user started sleep early');
  }

  /// Evaluates current water intake against an event-rank pace model (water + meds).
  /// Suppresses reminders if on pace, or customizes the message if behind.
  static Future<void> evaluateWaterPace() async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    final waterGoal = await DatabaseService.getSettingInt('water_goal', 3000);
    
    final reminders = await DatabaseService.getReminders(type: 'water');
    final activeWater = reminders.where((r) => (r['active'] as int) == 1).toList();
    final medicines = await DatabaseService.getMedicines();
    
    final List<Map<String, dynamic>> events = [];
    
    for (final r in activeWater) {
      events.add({
        'id': 2000 + (r['id'] as int),
        'hour': r['hour'] as int,
        'minute': r['minute'] as int,
        'title': '💧 Water Reminder',
        'isWater': true,
      });
    }
    
    for (final m in medicines) {
      final parts = (m['reminder_time'] as String).split(':');
      if (parts.length == 2) {
        events.add({
          'id': 1000 + (m['id'] as int),
          'hour': int.tryParse(parts[0]) ?? 9,
          'minute': int.tryParse(parts[1]) ?? 0,
          'title': '💊 Medicine Reminder',
          'isWater': false,
        });
      }
    }
    
    events.sort((a, b) {
      if (a['hour'] != b['hour']) return (a['hour'] as int).compareTo(b['hour'] as int);
      return (a['minute'] as int).compareTo(b['minute'] as int);
    });
    
    if (events.isEmpty) return;
    
    final pacePerEvent = waterGoal / events.length;
    final currentWater = await DatabaseService.getWaterTotal(todayStr);
    final nowMins = now.hour * 60 + now.minute;
    
    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final eventMins = (event['hour'] as int) * 60 + (event['minute'] as int);
      
      // We only care about water reminders that haven't passed yet today
      if (event['isWater'] == true && eventMins > nowMins) {
        final expectedWater = ((i + 1) * pacePerEvent).round();
        final notifId = event['id'] as int;
        
        if (currentWater >= expectedWater) {
          // On pace or ahead -> Suppress today
          await cancelNotification(notifId);
          await scheduleDailyNotificationFromTomorrow(
            id: notifId,
            title: event['title'] as String,
            body: 'Time to drink some water!',
            hour: event['hour'] as int,
            minute: event['minute'] as int,
          );
          await DatabaseService.suppressNotifForToday(notifId);
          print('evaluateWaterPace: Suppressed #$notifId (Current: $currentWater >= Expected: $expectedWater)');
        } else {
          // Behind pace -> Customize body and stop evaluation
          await cancelNotification(notifId);
          String newBody;
          if (i == 0 && currentWater == 0) {
            newBody = 'Day has started, start with a glass of water!';
          } else {
            final behind = expectedWater - currentWater;
            newBody = '💧 ${currentWater}ml logged — ${behind}ml behind pace';
          }
          
          await scheduleDailyNotification(
            id: notifId,
            title: event['title'] as String,
            body: newBody,
            hour: event['hour'] as int,
            minute: event['minute'] as int,
          );
          // We intentionally do NOT suppress it today, because we want this new message to fire.
          print('evaluateWaterPace: Updated #$notifId body to: "$newBody"');
          break; // Stop evaluating so subsequent reminders keep default behavior for now
        }
      }
    }
  }

  /// Suppresses a meal reminder if food logged matches keywords OR is within ±45 min.
  static Future<void> suppressMealReminderIfRelevant(String foodItem, {String? rawInput}) async {
    final activeFast = await DatabaseService.getActiveFast();
    if (activeFast != null) return; // Handled by rescheduleAll

    final itemLower = foodItem.toLowerCase();
    final rawLower = rawInput?.toLowerCase() ?? '';
    final keywords = <String>[];
    if (itemLower.contains('breakfast') || rawLower.contains('breakfast')) keywords.add('breakfast');
    if (itemLower.contains('lunch') || rawLower.contains('lunch')) keywords.add('lunch');
    if (itemLower.contains('dinner') || rawLower.contains('dinner')) keywords.add('dinner');

    final reminders = await DatabaseService.getReminders(type: 'meal');
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    for (final r in reminders) {
      if ((r['active'] as int) != 1) continue;
      final label = (r['label'] as String).toLowerCase();
      final rMins = (r['hour'] as int) * 60 + (r['minute'] as int);
      
      bool keywordMatch = keywords.any((kw) => label.contains(kw));
      bool timeMatch = (rMins - nowMins).abs() <= 45;

      if (keywordMatch || timeMatch) {
        final notifId = 3000 + (r['id'] as int);
        await cancelNotification(notifId);
        await scheduleDailyNotificationFromTomorrow(
          id: notifId,
          title: '🍽️ Meal Reminder',
          body: r['label'] as String,
          hour: r['hour'] as int,
          minute: r['minute'] as int,
        );
        await DatabaseService.suppressNotifForToday(notifId);
        print('Suppressed meal reminder #$notifId — Match(KW:$keywordMatch, Time:$timeMatch)');
      }
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

      // Also cancel native alarms for every ID we know how to schedule. Native
      // alarms are managed by AlarmManager and aren't touched by cancelAll().
      // We iterate medicines + reminders (active AND inactive) + singletons
      // so disabled-but-previously-scheduled IDs are cleared.
      final allMeds = await DatabaseService.getMedicines();
      final allReminders = await DatabaseService.getReminders();
      for (final m in allMeds) {
        await _cancelNative(1000 + (m['id'] as int));
      }
      for (final r in allReminders) {
        final id = r['id'] as int;
        await _cancelNative(2000 + id);
        await _cancelNative(3000 + id);
      }
      await _cancelNative(sleepReminderNotifId);
      await _cancelNative(summaryNotifId);
      await _cancelNative(weightReminderNotifId);

      // Remove stale suppression rows from previous days
      await DatabaseService.clearExpiredSuppressions();

      // Schedule medicine reminders
      final medicines = allMeds;
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

      // Schedule sleep reminder if enabled
      await scheduleSleepReminderIfEnabled();

      // Restore live fasting notification — rescheduleAll cancels ALL first
      if (activeFast != null) {
        final fastStart = DateTime.parse(activeFast['start_time'] as String);
        await showFastingNotification(fastStart);
        print('Restored fasting live notification after rescheduleAll');
      }

      // Restore live sleep notification — same reason
      final activeSleep = await DatabaseService.getActiveSleep();
      if (activeSleep != null) {
        final sleepStart = DateTime.parse(activeSleep['start_time'] as String);
        await showSleepNotification(sleepStart);
        print('Restored sleep live notification after rescheduleAll');
      }

      print('Rescheduled ${medicines.length} medicine + ${reminders.where((r) => (r['active'] as int) == 1).length} other reminders');

      // Finally, evaluate water pace to apply custom messages or suppressions based on the fresh schedule
      await evaluateWaterPace();
    } finally {
      _isRescheduling = false;
    }
  }
}

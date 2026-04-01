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
      matchDateTimeComponents: DateTimeComponents.time,
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
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_tracker_fasting',
          'Fasting Tracker',
          channelDescription: 'Live fasting progress notification',
          importance: Importance.low,      // low = silent, no heads-up popup
          priority: Priority.low,
          icon: '@mipmap/launcher_icon',
          ongoing: true,                  // can't be swiped away
          autoCancel: false,
          showWhen: false,                // hide timestamp – we have our own timer
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

  /// Reschedule all reminders from the database
  static Future<void> rescheduleAll() async {
    if (_isRescheduling) return;
    
    final now = DateTime.now();
    if (_lastReschedule != null && now.difference(_lastReschedule!).inSeconds < 5) {
      print('rescheduleAll debounced');
      return;
    }
    
    _isRescheduling = true;
    _lastReschedule = now;
    
    try {
      await cancelAll(); // Clean slate to avoid duplicates or orphaned alarms

      // Schedule medicine reminders
      final medicines = await DatabaseService.getMedicines();
      for (final med in medicines) {
        final parts = (med['reminder_time'] as String).split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 9;
          final minute = int.tryParse(parts[1]) ?? 0;
          final medId = 1000 + (med['id'] as int);
          await scheduleDailyNotification(
            id: medId,
            title: '💊 Medicine Reminder',
            body: 'Time to take ${med['name']}',
            hour: hour,
            minute: minute,
          );
        }
      }

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
          await scheduleDailyNotification(
            id: waterId,
            title: '💧 Water Reminder',
            body: label.isNotEmpty ? label : 'Time to drink some water!',
            hour: hour,
            minute: minute,
          );
        } else if (type == 'meal') {
          final mealId = 3000 + id;
          await scheduleDailyNotification(
            id: mealId,
            title: '🍽️ Meal Reminder',
            body: label.isNotEmpty ? label : 'Time to log your meal!',
            hour: hour,
            minute: minute,
          );
        }
      }

      print('Rescheduled ${medicines.length} medicine + ${reminders.where((r) => (r['active'] as int) == 1).length} other reminders');
    } finally {
      _isRescheduling = false;
    }
  }
}

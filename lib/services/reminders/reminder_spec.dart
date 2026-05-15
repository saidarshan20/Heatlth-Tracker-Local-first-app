// Reminder framework — see CLAUDE.md → "Adding a new reminder".
//
// Every scheduled (daily/weekly/repeating) notification in the app SHOULD
// implement [ReminderSpec]. The spec carries everything `rescheduleAll()` and
// the suppression layer need: identity, schedule, context-aware skip rules,
// and a hook for user actions that should defer today's fire.
//
// Live (persistent) notifications like the fasting/sleep chronometers are NOT
// reminders — they're shown on demand from the dashboard and don't go through
// this layer.

import '../database_service.dart';
import '../notification_service.dart';

/// Contract every recurring reminder implements.
///
/// Concrete examples live alongside this file (`sleep_reminder.dart`,
/// `medicine_reminder.dart`, …). Existing reminders still live inline inside
/// `NotificationService` for historical reasons; new reminders should go
/// through this abstraction.
abstract class ReminderSpec {
  /// Globally unique notification id. Must fit one of the documented ranges
  /// in CLAUDE.md → "Notification ID Scheme".
  int get notifId;

  /// Title shown when the notification fires.
  String get title;

  /// Body text shown when the notification fires.
  String get body;

  /// Returns the (hour, minute) for today's fire, or `null` if the user has
  /// disabled this reminder (in which case `rescheduleAll` will just cancel
  /// it). Read your enabled-flag + time from `DatabaseService` settings.
  Future<({int hour, int minute})?> getSchedule();

  /// Should today's fire be skipped? Return true when the user has already
  /// done the thing this reminder nags about (e.g. they're already sleeping,
  /// they just drank water, a fast is active for a meal reminder).
  ///
  /// Default: respect the persisted "suppressed for today" flag.
  Future<bool> shouldSuppressToday() async {
    return DatabaseService.isNotifSuppressedToday(notifId);
  }
}

/// Convenience: schedule [spec] for today, or defer to tomorrow if
/// `shouldSuppressToday()` returns true. Call this from `rescheduleAll()` or
/// any flow that needs to (re)install a reminder.
Future<void> scheduleReminder(ReminderSpec spec) async {
  final schedule = await spec.getSchedule();
  if (schedule == null) {
    await NotificationService.cancelNotification(spec.notifId);
    return;
  }
  final suppressed = await spec.shouldSuppressToday();
  if (suppressed) {
    await NotificationService.scheduleDailyNotificationFromTomorrow(
      id: spec.notifId,
      title: spec.title,
      body: spec.body,
      hour: schedule.hour,
      minute: schedule.minute,
    );
  } else {
    await NotificationService.scheduleDailyNotification(
      id: spec.notifId,
      title: spec.title,
      body: spec.body,
      hour: schedule.hour,
      minute: schedule.minute,
    );
  }
}

/// Call this when the user does the thing the reminder is nagging about
/// (logged water, started sleep, took meds). Cancels today's fire, persists
/// the "skip today" flag, and reschedules from tomorrow.
Future<void> suppressReminderForToday(ReminderSpec spec) async {
  await NotificationService.cancelNotification(spec.notifId);
  await DatabaseService.suppressNotifForToday(spec.notifId);
  final schedule = await spec.getSchedule();
  if (schedule == null) return;
  await NotificationService.scheduleDailyNotificationFromTomorrow(
    id: spec.notifId,
    title: spec.title,
    body: spec.body,
    hour: schedule.hour,
    minute: schedule.minute,
  );
}

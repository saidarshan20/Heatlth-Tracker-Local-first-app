package com.sai.health_tracker

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import java.util.Calendar

/**
 * Single-shot exact-alarm scheduler. Mirrors the working pattern used in the
 * sibling `Watery` project — each scheduled alarm is one-shot, and the
 * receiver re-arms it for tomorrow once it fires. No daily-repeat magic
 * (which doubles up on ColorOS), no `setAlarmClock` (which shows the
 * persistent alarm icon).
 */
object AlarmScheduler {
    const val CHANNEL_ID = "health_tracker_reminders"
    const val CHANNEL_NAME = "Health Tracker Reminders"

    const val EXTRA_NOTIF_ID = "notif_id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_HOUR = "hour"
    const val EXTRA_MINUTE = "minute"

    fun schedule(
        context: Context,
        notifId: Int,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        fromTomorrow: Boolean,
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildPendingIntent(context, notifId, title, body, hour, minute)

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (fromTomorrow || cal.timeInMillis <= System.currentTimeMillis()) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            }
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        }
    }

    fun cancel(context: Context, notifId: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildPendingIntent(context, notifId, "", "", 0, 0, mutable = false)
        am.cancel(pi)
        pi.cancel()
    }

    private fun buildPendingIntent(
        context: Context,
        notifId: Int,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        mutable: Boolean = true,
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.sai.health_tracker.FIRE_ALARM_$notifId"
            putExtra(EXTRA_NOTIF_ID, notifId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
        }
        return PendingIntent.getBroadcast(
            context, notifId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val ch = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Medicine, water, meal, sleep, and other daily reminders"
            enableLights(true)
            enableVibration(true)
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), audio)
        }
        nm.createNotificationChannel(ch)
    }
}

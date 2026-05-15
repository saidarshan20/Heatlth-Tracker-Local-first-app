package com.sai.health_tracker

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "health_tracker/alarms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: return@setMethodCallHandler result.error("ARG", "id required", null)
                        val title = call.argument<String>("title") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        val hour = call.argument<Int>("hour") ?: return@setMethodCallHandler result.error("ARG", "hour required", null)
                        val minute = call.argument<Int>("minute") ?: return@setMethodCallHandler result.error("ARG", "minute required", null)
                        val fromTomorrow = call.argument<Boolean>("fromTomorrow") ?: false
                        AlarmScheduler.ensureChannel(applicationContext)
                        AlarmScheduler.schedule(applicationContext, id, title, body, hour, minute, fromTomorrow)
                        result.success(null)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: return@setMethodCallHandler result.error("ARG", "id required", null)
                        AlarmScheduler.cancel(applicationContext, id)
                        result.success(null)
                    }
                    "canScheduleExact" -> {
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            am.canScheduleExactAlarms()
                        } else true
                        result.success(ok)
                    }
                    "requestExactPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

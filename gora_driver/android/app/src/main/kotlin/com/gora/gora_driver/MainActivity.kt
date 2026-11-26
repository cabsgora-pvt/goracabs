package com.gora.gora_driver

import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreen(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyLockScreen(intent)
    }

    // The full-screen "New ride request" notification launches this activity
    // with payload "ride_request" (flutter_local_notifications puts it in the
    // "payload" extra). Only for that launch is the app shown over the lock
    // screen with the screen turned on, so a request is seen on a locked phone.
    // The app clears it again ("releaseLockScreen") once the request screen
    // closes — the app is never left reachable over the keyguard.
    private fun applyLockScreen(intent: Intent?) {
        if (intent?.getStringExtra("payload") != "ride_request") return
        setLockScreen(true)
    }

    private fun setLockScreen(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gora/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "releaseLockScreen" -> {
                    setLockScreen(false)
                    result.success(true)
                }
                // Ride-request ringtone fallback: the phone's own notification
                // sound, when the admin ringtone and the bundled one both fail.
                "playSystemAlert" -> {
                    try {
                        ringtone?.stop()
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                        ringtone?.play()
                        result.success(ringtone != null)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopSystemAlert" -> {
                    try { ringtone?.stop() } catch (_: Exception) {}
                    ringtone = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try { ringtone?.stop() } catch (_: Exception) {}
        super.onDestroy()
    }
}

package com.gora.gora_driver

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null
    private var vibrating = false

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    // Ride request: buzz-buzz, pause — repeated until stopVibration.
    private fun startVibration(): Boolean {
        val v = vibrator() ?: return false
        if (!v.hasVibrator()) return false
        val pattern = longArrayOf(0, 700, 400, 700, 1200)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(pattern, 0)
        }
        vibrating = true
        return true
    }

    private fun stopVibration() {
        try { vibrator()?.cancel() } catch (_: Exception) {}
        vibrating = false
    }

    // A short beep + buzz (a new chat message from the rider).
    private fun beep() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 250)
            window.decorView.postDelayed({ try { tone.release() } catch (_: Exception) {} }, 600)
        } catch (_: Exception) {}
        if (vibrating) return
        try {
            val v = vibrator()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v?.vibrate(VibrationEffect.createOneShot(180, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(180)
            }
        } catch (_: Exception) {}
    }

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
                // Ride-request vibration, looping until stopped.
                "startVibration" -> {
                    result.success(try { startVibration() } catch (e: Exception) { false })
                }
                "stopVibration" -> {
                    stopVibration()
                    result.success(true)
                }
                "beep" -> {
                    beep()
                    result.success(true)
                }
                // The trip screen keeps the display on (FLAG_KEEP_SCREEN_ON is
                // window-scoped: it only applies while this activity is shown).
                "keepScreenOn" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try { ringtone?.stop() } catch (_: Exception) {}
        stopVibration()
        super.onDestroy()
    }
}

package com.example.sableen

import io.flutter.embedding.android.FlutterActivity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.round

class MainActivity : FlutterActivity() {
    private var requested = 0.0
    private var resumed = false
    private var display: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        display = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sableen/display")
        display?.setMethodCallHandler { call, result ->
            if (call.method == "cadence") {
                requested = (call.arguments as? Number)?.toDouble() ?: 0.0
                if (resumed) applyCadence(requested)
                result.success(null)
            } else when (call.method) {
                "supportsPip" -> result.success(supportsPip())
                "isPip" -> result.success(Build.VERSION.SDK_INT >= 24 && isInPictureInPictureMode)
                "enterPip" -> {
                    val aspect = (call.arguments as? Number)?.toDouble() ?: 1.0
                    val ratio = Rational((aspect.coerceIn(0.42, 2.38) * 1000).toInt(), 1000)
                    val entered = if (Build.VERSION.SDK_INT >= 26 && supportsPip() && resumed) {
                        try { enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(ratio).build()) }
                        catch (_: IllegalStateException) { false }
                    } else false
                    result.success(entered)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun supportsPip() = Build.VERSION.SDK_INT >= 26 &&
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        display?.invokeMethod("pipChanged", inPip)
    }

    @Suppress("DEPRECATION")
    private fun applyCadence(fps: Double) {
        if (android.os.Build.VERSION.SDK_INT < 23) return
        val screen = windowManager.defaultDisplay
        val active = screen.mode
        val target = if (fps.isFinite() && fps in 1.0..240.0) screen.supportedModes
            .filter { it.physicalWidth == active.physicalWidth && it.physicalHeight == active.physicalHeight }
            .filter { val multiple = round(it.refreshRate / fps); multiple >= 1 && abs(it.refreshRate - multiple * fps) <= 0.5 }
            .minWithOrNull(compareBy({ round(it.refreshRate / fps) }, { abs(it.refreshRate - round(it.refreshRate / fps) * fps) }, { it.modeId != active.modeId }))?.modeId ?: 0 else 0
        val params = window.attributes
        if (params.preferredDisplayModeId != target) {
            params.preferredDisplayModeId = target
            window.attributes = params
        }
    }

    override fun onPause() {
        resumed = false
        applyCadence(0.0)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        applyCadence(requested)
    }
}

package com.example.sableen

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.round

class MainActivity : FlutterActivity() {
    private var requested = 0.0
    private var resumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sableen/display").setMethodCallHandler { call, result ->
            if (call.method == "cadence") {
                requested = (call.arguments as? Number)?.toDouble() ?: 0.0
                if (resumed) applyCadence(requested)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
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
        requested = 0.0
        applyCadence(0.0)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        applyCadence(requested)
    }
}

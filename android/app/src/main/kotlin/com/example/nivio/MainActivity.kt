package com.example.nivio

import android.os.Build
import android.os.Bundle
import android.graphics.Rect
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nivio/gesture_exclusion"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "excludeBottomGestures" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val height = call.argument<Int>("height") ?: 200
                        val decorView = window.decorView
                        decorView.post {
                            val rect = Rect(
                                0,
                                decorView.height - height,
                                decorView.width,
                                decorView.height
                            )
                            decorView.systemGestureExclusionRects = listOf(rect)
                        }
                    }
                    result.success(true)
                }
                "clearGestureExclusion" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        window.decorView.systemGestureExclusionRects = emptyList()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

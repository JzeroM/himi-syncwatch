package com.himi.syncwatch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val dvChannel = MethodChannel(
        flutterEngine!!.dartExecutor.binaryMessenger,
        DolbyVisionPlugin.CHANNEL
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dvChannel.setMethodCallHandler(DolbyVisionPlugin())
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        dvChannel.setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

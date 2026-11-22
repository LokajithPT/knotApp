package com.example.knot_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "knot_app/sms_receiver"
        lateinit var smsChannel: MethodChannel
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        smsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        smsChannel.setMethodCallHandler { call, result ->
            if (call.method == "ping") {
                result.success("pong")
            } else {
                result.notImplemented()
            }
        }
    }
}

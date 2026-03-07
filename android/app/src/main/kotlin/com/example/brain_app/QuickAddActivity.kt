package com.example.brain_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class QuickAddActivity : FlutterActivity() {

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun getDartEntrypointFunctionName(): String {
        return "quickAddMain"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val mode = intent?.data?.getQueryParameter("mode") ?: "text"

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.brain_app/quick_add")
            .setMethodCallHandler { call, result ->
                if (call.method == "getMode") {
                    result.success(mode)
                } else {
                    result.notImplemented()
                }
            }
    }
}

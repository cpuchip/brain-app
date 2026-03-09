package com.example.brain_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WidgetFilterActivity : FlutterActivity() {

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun getDartEntrypointFunctionName(): String {
        return "widgetFilterMain"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val filterType = intent?.data?.getQueryParameter("type") ?: "practices"

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.brain_app/widget_filter")
            .setMethodCallHandler { call, result ->
                if (call.method == "getFilterType") {
                    result.success(filterType)
                } else {
                    result.notImplemented()
                }
            }
    }
}

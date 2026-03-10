package com.example.brain_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs

class QuickAddPracticeActivity : FlutterActivity() {

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun getDartEntrypointFunctionName(): String {
        return "quickAddPracticeMain"
    }
}

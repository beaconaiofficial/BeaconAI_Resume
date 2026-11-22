package dev.getbeaconai.beaconai_resume

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var ageSignalsChannel: AgeSignalsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ageSignalsChannel = AgeSignalsChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0,
        ) { this }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ageSignalsChannel?.dispose()
        ageSignalsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

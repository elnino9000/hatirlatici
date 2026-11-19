package com.hatirlatici.hatirlatici

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var bekliyor = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == "com.hatirlatici.SESLI") {
            bekliyor = true
            setIntent(Intent(Intent.ACTION_MAIN))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val k = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hatirlatici/hizli")
        k.setMethodCallHandler { call, result ->
            if (call.method == "sesliMi") {
                val b = bekliyor
                bekliyor = false
                result.success(b)
            } else {
                result.notImplemented()
            }
        }
        kanal = k
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "com.hatirlatici.SESLI") {
            setIntent(Intent(Intent.ACTION_MAIN))
            kanal?.invokeMethod("sesli", null)
        } else {
            setIntent(intent)
        }
    }
}

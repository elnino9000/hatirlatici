package com.hatirlatici.hatirlatici

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var bekliyor = false
    private var notlarBekliyor = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == "com.hatirlatici.SESLI") {
            bekliyor = true
            setIntent(Intent(Intent.ACTION_MAIN))
        } else if (intent?.action == "com.hatirlatici.NOTLAR") {
            notlarBekliyor = true
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
            } else if (call.method == "notlarMi") {
                val b = notlarBekliyor
                notlarBekliyor = false
                result.success(b)
            } else if (call.method == "widgetYenile") {
                NotWidget.yenile(applicationContext)
                result.success(null)
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
        } else if (intent.action == "com.hatirlatici.NOTLAR") {
            setIntent(Intent(Intent.ACTION_MAIN))
            kanal?.invokeMethod("notlar", null)
        } else {
            setIntent(intent)
        }
    }
}

package br.com.coliseu.sales

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — expõe canal nativo 'coliseu/device' para Dart.
 *
 * Canal: coliseu/device
 * Método: getAndroidId → retorna Settings.Secure.ANDROID_ID
 *   • Hardware-bound: único por device + APK signing key
 *   • Sobrevive a reinstalações do app
 *   • Muda apenas em factory reset
 *   • Não requer permissões (AccessLevel.EVERYONE)
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "coliseu/device"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> {
                        val androidId = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID
                        )
                        if (!androidId.isNullOrEmpty()) {
                            result.success(androidId)
                        } else {
                            result.error("UNAVAILABLE", "ANDROID_ID indisponível", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

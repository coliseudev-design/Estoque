package br.com.coliseusistemas.coliseu_estoque

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Expõe o ANDROID_ID ao Flutter (canal "coliseu/device") para o vínculo de licença
 * do aparelho no Coliseu.Identity — mesmo contrato do app de vendas.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coliseu/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidId") {
                    result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                } else {
                    result.notImplemented()
                }
            }
    }
}

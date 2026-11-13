package app.sweatik2.cloro

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // What the phone can run, for the Free plan's on-device AI
        // (lib/services/on_device_ai.dart): Android version, ABIs, memory, free space.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.cloro/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "capability" -> {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val memory = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(memory)
                    val free = try { StatFs(filesDir.absolutePath).availableBytes } catch (e: Exception) { 0L }
                    result.success(
                        mapOf(
                            "sdk" to Build.VERSION.SDK_INT,
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "totalRam" to memory.totalMem,
                            "freeBytes" to free,
                            "lowRam" to am.isLowRamDevice,
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}

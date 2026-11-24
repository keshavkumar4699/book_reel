package app.sweatik2.cloro

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var booksFolder: BooksFolder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The folder books are imported from by themselves (BooksFolder.kt).
        booksFolder = BooksFolder(this).also {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.cloro/books_folder").setMethodCallHandler(it)
        }
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
        // The screen stays on while reels are read aloud hands-free
        // (lib/services/screen_awake.dart): a phone that timed out would stop
        // them turning.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.cloro/screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepOn" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Android's folder picker answers here.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (booksFolder?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}

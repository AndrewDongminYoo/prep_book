package kr.donminzzi.prep_book

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    private data class PendingSave(
        val source: File,
        val result: MethodChannel.Result,
    )

    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prep_book/backup_save")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveBackup") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingSave != null) {
                    result.error("busy", "A backup save is already active.", null)
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                val fileName = call.argument<String>("fileName")
                if (path.isNullOrBlank() || fileName.isNullOrBlank() || File(fileName).name != fileName) {
                    result.error("invalid_name", "Invalid backup save input.", null)
                    return@setMethodCallHandler
                }
                val source =
                    try {
                        File(path).canonicalFile
                    } catch (_: IOException) {
                        result.error("invalid_source", "Invalid backup save input.", null)
                        return@setMethodCallHandler
                    }
                if (!source.path.startsWith(codeCacheDir.canonicalPath + File.separator) || !source.isFile) {
                    result.error("invalid_source", "Invalid backup save input.", null)
                    return@setMethodCallHandler
                }

                pendingSave = PendingSave(source, result)
                val intent =
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, SAVE_BACKUP_REQUEST)
                } catch (_: ActivityNotFoundException) {
                    pendingSave = null
                    result.error("save_failed", "No document picker is available.", null)
                }
            }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_BACKUP_REQUEST) return
        val pending = pendingSave ?: return
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingSave = null
            pending.result.success(false)
            return
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingSave = null
            pending.result.error("save_failed", "No backup destination was selected.", null)
            return
        }

        Thread {
            try {
                val output =
                    contentResolver.openOutputStream(uri)
                        ?: throw IOException("The backup destination could not be opened.")
                pending.source.inputStream().use { input ->
                    output.use { input.copyTo(it, 64 * 1024) }
                }
                runOnUiThread {
                    pendingSave = null
                    pending.result.success(true)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    pendingSave = null
                    pending.result.error("save_failed", "The backup could not be written.", null)
                }
            }
        }.start()
    }

    private companion object {
        const val SAVE_BACKUP_REQUEST = 0x5173
    }
}

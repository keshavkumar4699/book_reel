package app.sweatik2.cloro

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * A folder on the phone that books are imported from by themselves
 * (lib/services/books_folder.dart). Android's folder picker gives the app
 * that folder alone, kept across restarts until it's changed or removed, so
 * no storage permission is asked for.
 */
class BooksFolder(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "list" -> inBackground(result) { list(Uri.parse(call.argument<String>("uri")!!)) }
            "copy" -> inBackground(result) { copy(Uri.parse(call.argument<String>("uri")!!), call.argument<String>("id")!!) }
            "release" -> {
                release(Uri.parse(call.argument<String>("uri")!!))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                // The folder was moved or deleted, or its access was taken back.
                main.post { result.error("denied", e.message, null) }
            } catch (e: IllegalArgumentException) {
                main.post { result.error("denied", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder is already being picked", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            // It opens at Download, where most books land (Android 8 and later).
            if (Build.VERSION.SDK_INT >= 26) {
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Download"),
                )
            }
        }
        try {
            pending = result
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("unavailable", e.message, null)
        }
    }

    /** The picker answered; true when it was this class's request. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            result.error("denied", e.message, null)
            return true
        }
        val name = displayName(uri) ?: uri.lastPathSegment?.substringAfterLast(':')?.substringAfterLast('/') ?: ""
        result.success(mapOf("uri" to uri.toString(), "name" to name))
        return true
    }

    private fun displayName(tree: Uri): String? = try {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        activity.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    /** The EPUBs and PDFs in the folder and the folders in it (three deep). */
    private fun list(tree: Uri): List<Map<String, Any>> {
        val resolver = activity.contentResolver
        val books = ArrayList<Map<String, Any>>()
        val folders = java.util.ArrayDeque<Pair<String, Int>>()
        folders.add(DocumentsContract.getTreeDocumentId(tree) to 0)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        while (folders.isNotEmpty() && books.size < MAX_BOOKS) {
            val (parent, depth) = folders.pollFirst() ?: break
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            val cursor = resolver.query(children, columns, null, null, null)
                ?: if (depth == 0) throw SecurityException("The folder can't be read") else continue
            cursor.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: continue
                    if (name.startsWith(".")) continue
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < 3) folders.add(id to depth + 1)
                        continue
                    }
                    val lower = name.lowercase()
                    if (!lower.endsWith(".epub") && !lower.endsWith(".pdf")) continue
                    books.add(
                        mapOf(
                            "id" to id,
                            "name" to name,
                            "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                            "modified" to (if (c.isNull(4)) 0L else c.getLong(4)),
                        )
                    )
                }
            }
        }
        return books
    }

    /** A copy of one book in the app's cache, for the import to read (and then delete). */
    private fun copy(tree: Uri, id: String): String {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        val dir = File(activity.cacheDir, "books_folder").apply { mkdirs() }
        val out = File.createTempFile("book", ".tmp", dir)
        try {
            val input = activity.contentResolver.openInputStream(doc) ?: throw SecurityException("The book can't be read")
            input.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
        } catch (e: Exception) {
            out.delete()
            throw e
        }
        return out.absolutePath
    }

    private fun release(tree: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            // Already gone.
        }
    }

    companion object {
        const val REQUEST = 4210
        const val MAX_BOOKS = 2000
    }
}

package com.example.childapp.safety

import android.content.Context
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import java.util.concurrent.Executors

class MediaSafetyObserver(
    private val context: Context,
    handler: Handler = Handler(Looper.getMainLooper())
) : ContentObserver(handler) {

    companion object {
        private const val TAG = "MediaSafetyObserver"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val classifier by lazy { NsfwClassifier(context) }
    private var lastScannedUri: String? = null

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        if (uri == null) return

        executor.execute {
            try {
                scanMediaUri(uri)
            } catch (e: Exception) {
                Log.d(TAG, "Failed scanning media change: ${e.message}")
            }
        }
    }

    private fun scanMediaUri(uri: Uri) {
        val uriStr = uri.toString()
        if (uriStr == lastScannedUri) return
        lastScannedUri = uriStr

        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED
        )

        try {
            context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    val displayName = if (nameIdx >= 0) cursor.getString(nameIdx) else "Downloaded Image"

                    // Decode thumbnail bitmap safely
                    val bitmap = decodeSampledBitmapFromUri(uri, 224, 224) ?: return
                    val result = classifier.classify(bitmap)

                    if (result.isExplicit) {
                        Log.w(TAG, "Explicit image detected in gallery/download: $displayName (confidence: ${result.confidence})")
                        SafetyAlertSyncManager.recordAlert(
                            context = context,
                            alertType = "EXPLICIT_PHOTO_SAVED",
                            packageName = "com.android.providers.media",
                            appName = "Gallery / Downloads ($displayName)",
                            confidence = result.confidence.toDouble(),
                            severity = result.severity
                        )
                    }
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Error inspecting media URI: ${e.message}")
        }
    }

    private fun decodeSampledBitmapFromUri(uri: Uri, reqWidth: Int, reqHeight: Int): Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, options)
            }

            options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight)
            options.inJustDecodeBounds = false

            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, options)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.outHeight to options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}

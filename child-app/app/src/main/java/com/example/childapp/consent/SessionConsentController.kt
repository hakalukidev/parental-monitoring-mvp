package com.example.childapp.consent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.childapp.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MediaRequest(val sessionId: String, val kind: String, val facing: String = "BACK", val withAudio: Boolean = false, val receivedAt: Long = System.currentTimeMillis()) {
    val expired: Boolean get() = System.currentTimeMillis() - receivedAt >= 120_000
}

/** Pending approval lives only in memory; a process restart never restores a capture grant. */
object SessionConsentController {
    private val pendingState = MutableStateFlow<List<MediaRequest>>(emptyList())
    val pending = pendingState.asStateFlow()
    @Synchronized fun request(context: Context, request: MediaRequest) {
        if (pendingState.value.any { it.sessionId == request.sessionId }) return
        pendingState.value = (pendingState.value.filter { !it.expired } + request).takeLast(2)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("seftly_consent", "Seftly session requests", NotificationManager.IMPORTANCE_HIGH))
        val intent = Intent(context, SessionConsentActivity::class.java).putExtra("sessionId", request.sessionId)
        val tap = PendingIntent.getActivity(context, request.sessionId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            manager.notify(request.sessionId.hashCode(), NotificationCompat.Builder(context, "seftly_consent")
                .setSmallIcon(R.drawable.ic_seftly_notification).setContentTitle("Your parent wants to check in")
                .setContentText(if (request.kind == "screen") "Tap to review a screen-sharing request." else "Tap to review a camera${if (request.withAudio) " and microphone" else ""} request.")
                .setContentIntent(tap).setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH).build())
        } catch (_: SecurityException) { /* Pending request remains visible in the app if notifications are denied. */ }
    }
    @Synchronized fun clear(context: Context, sessionId: String) {
        pendingState.value = pendingState.value.filterNot { it.sessionId == sessionId }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(sessionId.hashCode())
    }
    @Synchronized fun clearAll(context: Context) { pendingState.value.toList().forEach { clear(context, it.sessionId) } }
    fun find(id: String) = pendingState.value.firstOrNull { it.sessionId == id && !it.expired }
    fun open(context: Context, id: String) { context.startActivity(Intent(context, SessionConsentActivity::class.java).putExtra("sessionId", id)) }
}

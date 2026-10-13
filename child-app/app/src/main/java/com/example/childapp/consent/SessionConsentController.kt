package com.example.childapp.consent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.app.Activity
import java.lang.ref.WeakReference
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.example.childapp.data.SessionStore
import com.example.childapp.audio.AudioCheckInService
import com.example.childapp.camera.CameraStreamService
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.childapp.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MediaRequest(val sessionId: String, val kind: String, val facing: String = "BACK", val withAudio: Boolean = false, val receivedAt: Long = System.currentTimeMillis()) {
    val expired: Boolean get() = System.currentTimeMillis() - receivedAt >= 120_000
}

/** Device actions live only in memory. No custom approval or saved projection grant. */
object SessionConsentController {
    private var foreground: WeakReference<Activity>? = null
    fun foreground(activity:Activity) {
        foreground=WeakReference(activity)
        pendingState.value.firstOrNull { !it.expired }?.let { request ->
            activity.window.decorView.post {if(foreground?.get()===activity&&!activity.isFinishing&&!activity.isDestroyed&&!activateGranted(activity,request,true))open(activity,request.sessionId)}
        }
    }
    fun background(activity:Activity) {if(foreground?.get()===activity)foreground=null}
    private val pendingState = MutableStateFlow<List<MediaRequest>>(emptyList())
    val pending = pendingState.asStateFlow()
    @Synchronized fun request(context: Context, request: MediaRequest) {
        if (pendingState.value.any { it.sessionId == request.sessionId }) return
        pendingState.value = (pendingState.value.filter { !it.expired } + request).takeLast(3)
        val visible=foreground?.get()
        if(visible!=null&&!visible.isFinishing&&!visible.isDestroyed) {
            visible.runOnUiThread {if(foreground?.get()===visible&&!activateGranted(visible,request,true))open(visible,request.sessionId)}
            return
        }
        if(context is com.example.childapp.service.ChildMonitoringService&&activateGranted(context,request,false))return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("seftly_device_actions_v3", "Seftly device actions", NotificationManager.IMPORTANCE_LOW).apply {setShowBadge(false)})
        val intent = Intent(context, SessionConsentActivity::class.java).putExtra("sessionId", request.sessionId)
        val tap = PendingIntent.getActivity(context, request.sessionId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            manager.notify(request.sessionId.hashCode(), NotificationCompat.Builder(context, "seftly_device_actions_v3")
                .setSmallIcon(R.drawable.ic_seftly_notification).setContentTitle("Your parent wants to check in")
                .setContentText(if (request.kind == "screen") "Open Seftly for Android's screen-sharing permission." else "Open Seftly for permitted ${if(request.kind=="audio")"microphone" else "camera"} activation.")
                .setContentIntent(tap).setAutoCancel(true).setOnlyAlertOnce(true).setPriority(NotificationCompat.PRIORITY_LOW).build())
        } catch (_: SecurityException) { /* Pending request remains visible in the app if notifications are denied. */ }
    }
    @Synchronized fun clear(context: Context, sessionId: String) {
        pendingState.value = pendingState.value.filterNot { it.sessionId == sessionId }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(sessionId.hashCode())
    }
    @Synchronized fun clearAll(context: Context) { pendingState.value.toList().forEach { clear(context, it.sessionId) } }
    fun find(id: String) = pendingState.value.firstOrNull { it.sessionId == id && !it.expired }
    private fun activateGranted(context:Context,request:MediaRequest,visible:Boolean):Boolean {
        if(request.expired)return false
        val required=if(request.kind=="audio")listOf(Manifest.permission.RECORD_AUDIO) else listOf(Manifest.permission.CAMERA)+(if(request.withAudio)listOf(Manifest.permission.RECORD_AUDIO) else emptyList())
        val granted=required.all {ContextCompat.checkSelfPermission(context,it)==PackageManager.PERMISSION_GRANTED}
        if(!MediaActivationPolicy.canUseExistingGrant(Build.VERSION.SDK_INT,request.kind,granted,visible))return false
        val session=SessionStore(context);if(!session.isSetupCompleted)return false
        val token=session.accessToken ?: return false
        return try {
            if(request.kind=="audio")AudioCheckInService.start(context,token,request.sessionId)
            else CameraStreamService.start(context,token,request.sessionId,request.facing,request.withAudio)
            clear(context,request.sessionId);true
        }catch(_:Exception){false} // OEM/platform refusal falls back to a visible Android action, never a bypass.
    }
    fun open(context: Context, id: String) { context.startActivity(Intent(context, SessionConsentActivity::class.java).putExtra("sessionId", id)) }
}

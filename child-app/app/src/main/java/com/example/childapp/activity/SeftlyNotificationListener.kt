package com.example.childapp.activity

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import kotlinx.coroutines.*
import org.json.JSONObject
import java.time.Instant

/** Metadata only: never reads notification extras, titles, text, OTPs or message bodies. */
class SeftlyNotificationListener : NotificationListenerService() {
    private val scope=CoroutineScope(Dispatchers.IO+SupervisorJob())
    private val recent=LinkedHashMap<String,Long>()
    override fun onListenerConnected() {connected=true;ActivitySync.schedule(this);super.onListenerConnected()}
    override fun onListenerDisconnected() {connected=false;super.onListenerDisconnected()}
    override fun onNotificationPosted(sbn:StatusBarNotification) {
        val now=System.currentTimeMillis(); val key=ActivityMetadata.hash(sbn.key)
        val prior=recent[key]
        if(prior != null && now-prior<30_000) return // Coalesce repeated/update callback storms.
        recent[key]=now
        while(recent.size>500)recent.remove(recent.keys.first())
        capture(sbn,if(prior==null)"POSTED" else "UPDATED",key,now)
    }
    override fun onNotificationRemoved(sbn:StatusBarNotification) {val key=ActivityMetadata.hash(sbn.key);recent.remove(key);capture(sbn,"REMOVED",key,System.currentTimeMillis())}
    private fun capture(sbn:StatusBarNotification,type:String,key:String,at:Long) {
        if(ActivityMetadata.sensitivePackage(sbn.packageName) || sbn.packageName==packageName)return
        val session=SessionStore(this); val child=session.childId ?: return
        if(session.accessToken==null)return
        scope.launch {
            if(SessionStore(this@SeftlyNotificationListener).childId!=child)return@launch
            val db=LocalDatabase.getInstance(this@SeftlyNotificationListener)
            val data=db.localState("activity_policy")?.let {runCatching {JSONObject(it)}.getOrNull()} ?: return@launch
            val policy=data.optJSONObject("policy") ?: return@launch
            if(data.optJSONObject("features")?.optBoolean("notifications") != true || !policy.optBoolean("notificationsEnabled"))return@launch
            val allowed=policy.optJSONArray("monitoredPackages") ?: return@launch
            if((0 until allowed.length()).none {allowed.optString(it)==sbn.packageName})return@launch
            val timestamp=if(type=="REMOVED")at else sbn.postTime.takeIf {it>0&&it<=at+300_000} ?: at
            db.queueActivity(JSONObject().put("kind","NOTIFICATION").put("eventId",ActivityMetadata.hash("$child:$key:$type:$timestamp")).put("eventAt",Instant.ofEpochMilli(timestamp).toString()).put("packageName",sbn.packageName).put("eventType",type),child)
            ActivitySync.schedule(this@SeftlyNotificationListener)
        }
    }
    override fun onDestroy() {connected=false;scope.cancel();super.onDestroy()}
    companion object {@Volatile var connected=false}
}

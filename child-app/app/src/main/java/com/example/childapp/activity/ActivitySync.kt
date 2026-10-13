package com.example.childapp.activity

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.safety.ApprovedSafetyModel
import com.example.childapp.communication.CommunicationSync
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit

object ActivitySync {
    private val lock=Mutex()
    private val kinds=listOf("NOTIFICATION","CALL","SMS","SAFETY")
    fun schedule(context:Context) {
        if(SessionStore(context).accessToken==null)return
        val constraints=Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val manager=WorkManager.getInstance(context)
        manager.enqueueUniqueWork("seftly_activity_sync",ExistingWorkPolicy.KEEP,OneTimeWorkRequestBuilder<ActivityWorker>().setConstraints(constraints).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build())
        manager.enqueueUniquePeriodicWork("seftly_activity_periodic",ExistingPeriodicWorkPolicy.KEEP,PeriodicWorkRequestBuilder<ActivityWorker>(15,TimeUnit.MINUTES).setConstraints(constraints).build())
    }
    fun stop(context:Context) {WorkManager.getInstance(context).cancelUniqueWork("seftly_activity_sync");WorkManager.getInstance(context).cancelUniqueWork("seftly_activity_periodic");WorkManager.getInstance(context).cancelAllWorkByTag("seftly_safety_scan")}
    fun notificationAccess(context:Context)=context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
    fun access(context:Context,permission:String)=if(permission in listOf(Manifest.permission.READ_CALL_LOG,Manifest.permission.READ_SMS)&&!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY))"UNAVAILABLE" else if(ContextCompat.checkSelfPermission(context,permission)==PackageManager.PERMISSION_GRANTED)"GRANTED" else "DENIED_OR_RESTRICTED"
    private fun identity(context:Context,child:String) {if(SessionStore(context).childId!=child||SessionStore(context).accessToken==null)throw CancellationException("Account changed")}
    suspend fun sync(context:Context)=lock.withLock {
        val child=SessionStore(context).childId ?: return@withLock
        val db=LocalDatabase.getInstance(context);val api=ApiClient(SessionStore(context))
        val response=api.getActivityPolicy();identity(context,child)
        db.setLocalState("activity_policy",response.put("childId",child).toString())
        val policy=response.optJSONObject("policy") ?: return@withLock
        val features=response.optJSONObject("features") ?: return@withLock
        if(features.optBoolean("communications"))CommunicationSync.sync(context,child,response)
        else {
            com.example.childapp.communication.CommunicationQueue(context).use { it.clear() }
            if(features.optBoolean("callSms")&&policy.optBoolean("callsEnabled"))collect(context,child,"CALL",Manifest.permission.READ_CALL_LOG)
            if(features.optBoolean("callSms")&&policy.optBoolean("smsEnabled"))collect(context,child,"SMS",Manifest.permission.READ_SMS)
        }
        identity(context,child)
        val manifest=ApprovedSafetyModel.manifest(context)
        val modelReady=manifest!=null&&db.localState("safety_model_ready")==manifest.getString("version")+":"+manifest.getString("sha256")
        val capabilities=JSONObject().put("notificationAccess",if(notificationAccess(context))"GRANTED" else "DENIED_OR_RESTRICTED")
            .put("listenerConnected",SeftlyNotificationListener.connected)
            .put("callLogAccess",db.localState("CALL_access")?.takeIf {access(context,Manifest.permission.READ_CALL_LOG)=="GRANTED"} ?: access(context,Manifest.permission.READ_CALL_LOG))
            .put("smsAccess",db.localState("SMS_access")?.takeIf {access(context,Manifest.permission.READ_SMS)=="GRANTED"} ?: access(context,Manifest.permission.READ_SMS))
            .put("safetyModel",if(modelReady)"AVAILABLE" else "UNAVAILABLE").put("sourceCoverage","SELECTED_MEDIA_ONLY")
            .put("queuedEvents",db.activityQueueCount()).put("droppedEvents",db.localState("activity_dropped")?.toIntOrNull() ?: 0)
        api.reportActivityCapabilities(capabilities);identity(context,child)
        for(kind in kinds) {
            val enabled=when(kind) {"NOTIFICATION"->features.optBoolean("notifications")&&policy.optBoolean("notificationsEnabled");"CALL"->features.optBoolean("callSms")&&policy.optBoolean("callsEnabled");"SMS"->features.optBoolean("callSms")&&policy.optBoolean("smsEnabled");else->features.optBoolean("safety")&&policy.optBoolean("safetyEnabled")}
            if(!enabled) {db.clearPendingActivity(kind);continue}
            repeat(5) {
                identity(context,child)
                val pending=db.pendingActivity(kind)
                if(kind=="NOTIFICATION") {
                    val packages=policy.optJSONArray("monitoredPackages") ?: JSONArray()
                    val allowed=(0 until packages.length()).map {packages.optString(it)}.toSet()
                    val excluded=pending.filter {it.optString("packageName") !in allowed||ActivityMetadata.sensitivePackage(it.optString("packageName"))}
                    db.markActivitySynced(kind,excluded.map {it.getString("eventId")})
                    if(excluded.isNotEmpty())return@repeat
                }
                val accessKey=when(kind){"NOTIFICATION"->"notificationAccess";"CALL"->"callLogAccess";"SMS"->"smsAccess";else->null}
                if(accessKey!=null&&capabilities.optString(accessKey)!="GRANTED") {db.clearPendingActivity(kind);return@repeat}
                if(pending.isNotEmpty()) {
                    val result=api.ingestActivity(JSONArray().apply {pending.forEach {put(it)}},child)
                    identity(context,child)
                    val receipts=result.optJSONArray("accepted") ?: JSONArray()
                    db.markActivitySynced(kind,(0 until receipts.length()).map {receipts.getString(it)})
                    db.setLocalState("activity_last_sync",Instant.now().toString())
                }
            }
        }
    }
    /** Supported public providers only. SMS body/contact databases/conversations are never queried. */
    private fun collect(context:Context,child:String,kind:String,permission:String) {
        if(access(context,permission)!="GRANTED")return
        val db=LocalDatabase.getInstance(context)
        val started=db.localState("${kind}_collection_start")?.toLongOrNull() ?: System.currentTimeMillis().also {db.setLocalState("${kind}_collection_start",it.toString())}
        val after=db.localState("${kind}_watermark")?.toLongOrNull() ?: started
        val salt=db.localState("activity_identifier_salt") ?: UUID.randomUUID().toString().also {db.setLocalState("activity_identifier_salt",it)}
        val uri=Uri.parse(if(kind=="CALL")"content://call_log/calls" else "content://sms")
        val columns=if(kind=="CALL")arrayOf("_id","date","type","duration","number") else arrayOf("_id","date","type","address")
        try {
            var newest=after;var count=0
            context.contentResolver.query(uri,columns,"date >= ?",arrayOf(after.toString()),"date ASC")?.use {cursor ->
                while(cursor.moveToNext()&&count<500) {
                    identity(context,child)
                    val id=cursor.getString(0);val at=cursor.getLong(1);val type=cursor.getInt(2)
                    if(at<=0||at>System.currentTimeMillis()+300_000)continue
                    val direction=if(kind=="CALL")ActivityMetadata.callDirection(type) else ActivityMetadata.smsDirection(type)
                    newest=maxOf(newest,at);count++
                    if(direction==null)continue
                    val identifier=cursor.getString(if(kind=="CALL")4 else 3) ?: ""
                    val event=JSONObject().put("kind",kind).put("eventId",ActivityMetadata.hash("$kind:$id:$at:$type"))
                        .put("eventAt",Instant.ofEpochMilli(at).toString()).put("direction",direction)
                    if(identifier.isNotBlank()) {
                        event.put("identifierHash",ActivityMetadata.hash("$salt:$identifier"))
                        ActivityMetadata.maskedIdentifier(identifier)?.let {event.put("maskedIdentifier",it)}
                    }
                    if(kind=="CALL")event.put("durationSeconds",cursor.getLong(3).coerceIn(0,86400))
                    db.queueActivity(event,child)
                }
            }
            db.setLocalState("${kind}_watermark",newest.toString());db.setLocalState("${kind}_access","GRANTED")
        } catch(_:SecurityException) {db.setLocalState("${kind}_access","RESTRICTED")}
        catch(_:IllegalArgumentException) {db.setLocalState("${kind}_access","UNAVAILABLE")}
    }
}

class ActivityWorker(context:Context,params:WorkerParameters):CoroutineWorker(context,params) {
    override suspend fun doWork():Result {
        if(SessionStore(applicationContext).accessToken==null)return Result.success()
        return try {ActivitySync.sync(applicationContext);Result.success()}
        catch(e:CancellationException) {throw e}
        catch(_:Exception) {Result.retry()}
    }
}

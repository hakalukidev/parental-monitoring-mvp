package com.example.childapp.communication

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat
import com.example.childapp.activity.ActivityMetadata
import com.example.childapp.activity.ActivitySync
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** Public, permission-authorized providers only. Never opens private app stores or writes/records calls. */
object CommunicationSync {
    private fun identity(context:Context,child:String){if(SessionStore(context).childId!=child||SessionStore(context).accessToken==null)throw CancellationException("Account changed")}
    fun sync(context:Context,child:String,response:JSONObject) {
        identity(context,child)
        val db=LocalDatabase.getInstance(context);val api=ApiClient(SessionStore(context));val policy=response.optJSONObject("policy") ?: return
        val enabled=response.optJSONObject("features")?.optBoolean("communications")==true&&policy.optBoolean("fullCommunicationHistoryEnabled")
        CommunicationQueue(context).use {queue ->
            val signature=listOf(enabled,policy.optBoolean("callsEnabled"),policy.optBoolean("smsEnabled"),policy.optBoolean("messageBodiesEnabled"),policy.optBoolean("contactsEnabled"),policy.optBoolean("mmsEnabled"),policy.optInt("initialImportDays",7),policy.optInt("retentionDays",30)).joinToString(":")
            if(db.localState("communication_scope")!=signature){queue.clear();db.setLocalState("communication_scope",signature);for(kind in listOf("CALL","SMS","MMS")){db.setLocalState("COMM_${kind}_cursor","");db.setLocalState("COMM_${kind}_window_end","");db.setLocalState("COMM_${kind}_last_poll","")}}
            val caps=capabilities(context,db,queue,child)
            api.reportCommunicationCapabilities(caps);identity(context,child)
            // A physical QA phone may have real communications: never use them as automated fixtures.
            if(com.example.childapp.BuildConfig.QA_SAFE_FIXTURES&&Build.HARDWARE !in setOf("ranchu","goldfish")){queue.clear();return}
            if(!enabled){queue.clear();return}
            for(kind in listOf("CALL","SMS")) {
                val requested=policy.optBoolean(if(kind=="CALL")"callsEnabled" else "smsEnabled")
                val permission=if(kind=="CALL")Manifest.permission.READ_CALL_LOG else Manifest.permission.READ_SMS
                if(!requested||ActivitySync.access(context,permission)!="GRANTED"){queue.clear(kind);continue}
                collect(context,child,kind,policy,queue,db)
                if(kind=="SMS"&&policy.optBoolean("mmsEnabled"))collect(context,child,"MMS",policy,queue,db)
                identity(context,child)
                // A provider failure after a grant is reported as restricted, never as complete coverage.
                api.reportCommunicationCapabilities(capabilities(context,db,queue,child));identity(context,child)
                if(db.localState("COMM_${kind}_access")=="RESTRICTED"||db.localState("COMM_${kind}_access")=="UNAVAILABLE"){queue.clear(kind);continue}
                repeat(12) {
                    identity(context,child);val pending=queue.pending(child,kind)
                    if(ActivitySync.access(context,permission)!="GRANTED"){queue.clear(kind);return@repeat}
                    if(pending.isNotEmpty()){
                        val result=api.ingestCommunications(JSONArray().apply {pending.forEach {put(it)}},child);identity(context,child)
                        val accepted=result.optJSONArray("accepted") ?: JSONArray()
                        queue.accepted(child,(0 until accepted.length()).map {accepted.getString(it)})
                    }
                }
            }
        }
    }
    private fun capabilities(context:Context,db:LocalDatabase,queue:CommunicationQueue,child:String):JSONObject {
        fun access(kind:String,permission:String):String=if(ActivitySync.access(context,permission)!="GRANTED")ActivitySync.access(context,permission) else db.localState("COMM_${kind}_access") ?: "GRANTED"
        val call=access("CALL",Manifest.permission.READ_CALL_LOG);val sms=access("SMS",Manifest.permission.READ_SMS)
        val telecom=context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
        return JSONObject().put("protocolVersion",2).put("androidApi",Build.VERSION.SDK_INT).put("callLogAccess",call).put("smsAccess",sms)
            .put("contactsAccess",ActivitySync.access(context,Manifest.permission.READ_CONTACTS)).put("defaultSmsRole",Telephony.Sms.getDefaultSmsPackage(context)==context.packageName)
            .put("defaultDialerRole",runCatching {telecom?.defaultDialerPackage==context.packageName}.getOrDefault(false))
            .put("callCoverage",if(call=="GRANTED")"PUBLIC_CALL_LOG" else "UNAVAILABLE").put("smsCoverage",if(sms=="GRANTED")"PUBLIC_SMS_PROVIDER" else "UNAVAILABLE")
            .put("mmsCoverage",if(sms=="GRANTED"&&db.localState("COMM_MMS_access")=="GRANTED")"PROVIDER_TEXT_METADATA" else "UNAVAILABLE")
            .put("queuedRecords",queue.count(child)).put("droppedRecords",db.localState("communications_dropped")?.toIntOrNull() ?: 0)
            .apply {db.localState("COMM_CALL_scan_at")?.let {put("lastCallScanAt",it)};db.localState("COMM_SMS_scan_at")?.let {put("lastMessageScanAt",it)}}
    }
    private fun collect(context:Context,child:String,transport:String,policy:JSONObject,queue:CommunicationQueue,db:LocalDatabase) {
        val now=System.currentTimeMillis();val activeWindow=db.localState("COMM_${transport}_window_end")?.toLongOrNull()
        val dirty=db.localState("COMM_${transport}_dirty")=="true"
        if(activeWindow==null&&!dirty&&now-(db.localState("COMM_${transport}_last_poll")?.toLongOrNull() ?: 0)<300000)return
        val initialDays=policy.optInt("initialImportDays",7).coerceIn(1,30).coerceAtMost(policy.optInt("retentionDays",30))
        val importStart=now-initialDays*86400000L
        val cursor=db.localState("COMM_${transport}_cursor")?.split(':')
        val lower=cursor?.firstOrNull()?.toLongOrNull() ?: importStart
        val rowId=cursor?.getOrNull(1)?.toLongOrNull() ?: -1
        val until=activeWindow ?: now.also {db.setLocalState("COMM_${transport}_window_end",it.toString())}
        val uri=when(transport){"CALL"->CallLog.Calls.CONTENT_URI;"SMS"->Telephony.Sms.CONTENT_URI;else->Telephony.Mms.CONTENT_URI}
        val dateColumn="date";val factor=if(transport=="MMS")1000L else 1L
        val bodies=policy.optBoolean("messageBodiesEnabled");val contacts=policy.optBoolean("contactsEnabled")
        val base=when(transport){"CALL"->arrayOf("_id","date","type","duration","number");"SMS"->arrayOf("_id","date","type","address","thread_id","read","status")+(if(bodies)arrayOf("body") else emptyArray());else->arrayOf("_id","date","msg_box","thread_id","read","m_type")}
        val extended=when(transport){"CALL"->base+arrayOf(CallLog.Calls.PHONE_ACCOUNT_ID,CallLog.Calls.PHONE_ACCOUNT_COMPONENT_NAME)+(if(contacts)arrayOf(CallLog.Calls.CACHED_NAME) else emptyArray());"SMS"->base+arrayOf("date_sent","sub_id");else->base+arrayOf("sub_id")}
        val selection="$dateColumn >= ? AND $dateColumn <= ? AND ($dateColumn > ? OR ($dateColumn = ? AND _id > ?))"
        val args=arrayOf((importStart/factor).toString(),(until/factor).toString(),(lower/factor).toString(),(lower/factor).toString(),rowId.toString())
        val names=mutableMapOf<String,String?>()
        try {
            var count=0;var newest=lower;var lastId=rowId
            val result=try {context.contentResolver.query(uri,extended,selection,args,"date ASC, _id ASC")}catch(_:IllegalArgumentException){context.contentResolver.query(uri,base,selection,args,"date ASC, _id ASC")}
            if(result==null){db.setLocalState("COMM_${transport}_access","UNAVAILABLE");return}
            result.use {rows ->
                fun text(column:String):String?=rows.getColumnIndex(column).takeIf {it>=0}?.let {if(rows.isNull(it))null else rows.getString(it)}
                while(rows.moveToNext()&&count<500){
                    identity(context,child)
                    val id=text("_id")?.toLongOrNull() ?: continue;val at=(text("date")?.toLongOrNull() ?: continue)*factor
                    newest=at;lastId=id;count++
                    if(at<=0||at>now+300000)continue
                    val direction=if(transport=="CALL")ActivityMetadata.callDirection(text("type")?.toIntOrNull() ?: -1) else ActivityMetadata.smsDirection(text(if(transport=="SMS")"type" else "msg_box")?.toIntOrNull() ?: -1)
                    if(direction==null)continue
                    val event=JSONObject().put("kind",if(transport=="CALL")"CALL" else "SMS").put("transport",transport).put("sourceId",id.toString())
                        .put("eventAt",Instant.ofEpochMilli(at).toString()).put("observedAt",Instant.ofEpochMilli(now).toString()).put("direction",direction)
                    var address=if(transport=="CALL")text("number") ?: "" else if(transport=="SMS")text("address") ?: "" else mmsAddress(context,id,direction)
                    address=address.take(255)
                    if(transport=="CALL"){
                        text("duration")?.toLongOrNull()?.let {event.put("durationSeconds",it.coerceIn(0,86400))};if(address.isNotBlank())event.put("phoneNumber",address)
                        text(CallLog.Calls.PHONE_ACCOUNT_ID)?.let {event.put("phoneAccountId",it.take(255))};text(CallLog.Calls.PHONE_ACCOUNT_COMPONENT_NAME)?.let {event.put("phoneAccountComponent",it.take(255))}
                    }else{
                        if(address.isNotBlank())event.put("address",address)
                        text("thread_id")?.let {event.put("threadId",it)};text("read")?.toIntOrNull()?.takeIf {it==0||it==1}?.let {event.put("read",it==1)}
                        val sent=text("date_sent")?.toLongOrNull();if(sent!=null&&sent>0&&sent<=now+300000)event.put("dateSent",Instant.ofEpochMilli(sent).toString())
                        event.put("deliveryStatus",CommunicationPrivacy.deliveryStatus(text("status")?.toIntOrNull()))
                        val parts=if(transport=="MMS")mmsParts(context,id,bodies) else null
                        val raw=if(transport=="SMS")text("body") else parts?.first
                        val safe=CommunicationPrivacy.body(raw,address,bodies);event.put("contentStatus",safe.status);safe.text?.let {event.put("body",it)}
                        if(transport=="MMS"){text("m_type")?.toIntOrNull()?.let {event.put("mmsType",it)};event.put("attachmentCount",parts?.second ?: 0)}
                    }
                    text("sub_id")?.let {event.put("subscriptionId",it.take(255))}
                    if(contacts){
                        val cached=if(transport=="CALL")text(CallLog.Calls.CACHED_NAME)?.takeIf {it.isNotBlank()} else null
                        val name=cached ?: if(ContextCompat.checkSelfPermission(context,Manifest.permission.READ_CONTACTS)==PackageManager.PERMISSION_GRANTED)names.getOrPut(address){contact(context,address)} else null
                        if(name!=null){event.put("contactName",name.take(255));event.put("contactSource",if(cached!=null)"CACHED_CALL_LOG" else "CONTACTS_PROVIDER")}
                    }
                    queue.offer(child,event)
                }
            }
            db.setLocalState("COMM_${transport}_access","GRANTED");db.setLocalState("COMM_${if(transport=="CALL")"CALL" else "SMS"}_scan_at",Instant.now().toString())
            if(count>=500){db.setLocalState("COMM_${transport}_cursor","$newest:$lastId")}
            else {
                // Revisit the import window in bounded pages so later duration/read/delivery changes are reflected.
                db.setLocalState("COMM_${transport}_cursor","");db.setLocalState("COMM_${transport}_window_end","")
                db.setLocalState("COMM_${transport}_last_poll",now.toString());db.setLocalState("COMM_${transport}_dirty","false")
            }
        }catch(_:SecurityException){db.setLocalState("COMM_${transport}_access","RESTRICTED")}
        catch(_:IllegalArgumentException){db.setLocalState("COMM_${transport}_access","UNAVAILABLE")}
    }
    private fun contact(context:Context,address:String):String? {
        if(address.isBlank())return null
        return try {context.contentResolver.query(Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI,Uri.encode(address)),arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),null,null,null)?.use {if(it.moveToFirst())it.getString(0) else null}}catch(_:SecurityException){null}
    }
    private fun mmsAddress(context:Context,id:Long,direction:String):String {
        return context.contentResolver.query(Uri.parse("content://mms/$id/addr"),arrayOf("address","type"),null,null,null)?.use {rows ->
            val addresses=mutableListOf<String>();val wanted=if(direction=="INCOMING")137 else 151
            while(rows.moveToNext()){val value=rows.getString(0) ?: continue;if(rows.getInt(1)==wanted&&value!="insert-address-token"&&value.isNotBlank())addresses.add(value)};addresses.distinct().joinToString(", ")
        } ?: ""
    }
    private fun mmsParts(context:Context,id:Long,bodies:Boolean):Pair<String?,Int> {
        val text=mutableListOf<String>();var attachments=0;var size=0;var unavailable=false
        context.contentResolver.query(Uri.parse("content://mms/part"),if(bodies)arrayOf("_id","ct","text") else arrayOf("_id","ct"),"mid = ?",arrayOf(id.toString()),"_id ASC")?.use {rows ->
            while(rows.moveToNext()&&attachments+text.size<100){if(rows.getString(1)=="text/plain"){if(bodies){val part=rows.getString(2);if(part==null){unavailable=true;continue};size+=part.length;if(size>32000)return Pair(" ".repeat(32001),attachments);text.add(part)}}else if(rows.getString(1)!="application/smil")attachments++}
        }
        return Pair(if(bodies&&!unavailable)CommunicationPrivacy.assembleTextParts(text) else null,attachments)
    }
}

package com.example.childapp.safety

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.work.*
import com.example.childapp.activity.ActivityMetadata
import com.example.childapp.activity.ActivitySync
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** Processes only a URI explicitly granted by OpenDocument. No library enumeration or raw upload. */
class SelectedMediaWorker(context:Context,params:WorkerParameters):CoroutineWorker(context,params) {
    override suspend fun doWork():Result {
        val uri=Uri.parse(inputData.getString("uri") ?: return Result.failure())
        val child=inputData.getString("child") ?: return Result.failure()
        val db=LocalDatabase.getInstance(applicationContext)
        if(uri.scheme!="content"||SessionStore(applicationContext).childId!=child)return Result.failure()
        val model=ApprovedSafetyModel.open(applicationContext) ?: run {
            runCatching {applicationContext.contentResolver.releasePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION)}
            return Result.failure(workDataOf("reason" to "Validated safety model unavailable"))
        }
        db.setLocalState("safety_model_ready",model.version+":"+model.manifest.getString("sha256"))
        var finished=false
        fun failed():Result {finished=true;return Result.failure()}
        try {
            val config=db.localState("activity_policy")?.let {JSONObject(it)} ?: return failed()
            if(config.optJSONObject("features")?.optBoolean("safety")!=true||config.optJSONObject("policy")?.optBoolean("safetyEnabled")!=true)return failed()
            val approved=config.optJSONArray("approvedModels") ?: return failed()
            if((0 until approved.length()).none {approved.optString(it)==model.version})return failed()
            val mime=applicationContext.contentResolver.getType(uri) ?: return failed()
            var size=-1L
            applicationContext.contentResolver.query(uri,arrayOf(OpenableColumns.SIZE),null,null,null)?.use {if(it.moveToFirst()&&!it.isNull(0))size=it.getLong(0)}
            require(size in 1..100*1024*1024)
            val mediaType=if(mime in setOf("image/jpeg","image/png","image/webp"))"IMAGE" else if(mime.startsWith("video/"))"VIDEO" else error("Unsupported media")
            val eventId=ActivityMetadata.hash("$child:$uri:$size:${model.version}")
            val resumeKey="safety_resume_$eventId"
            val decision=if(mediaType=="IMAGE") {
                val bitmap=if(Build.VERSION.SDK_INT>=28)ImageDecoder.decodeBitmap(ImageDecoder.createSource(applicationContext.contentResolver,uri)) {decoder,info,_ ->
                    require(info.size.width.toLong()*info.size.height<=50_000_000)
                    decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setTargetSampleSize(maxOf(1,maxOf(info.size.width,info.size.height)/1024))
                } else {
                    val options=BitmapFactory.Options().apply {inJustDecodeBounds=true}
                    applicationContext.contentResolver.openInputStream(uri)?.use {BitmapFactory.decodeStream(it,null,options)}
                    require(options.outWidth>0&&options.outHeight>0&&options.outWidth.toLong()*options.outHeight<=50_000_000)
                    options.inJustDecodeBounds=false;options.inSampleSize=1
                    while(maxOf(options.outWidth,options.outHeight)/options.inSampleSize>1024)options.inSampleSize*=2
                    applicationContext.contentResolver.openInputStream(uri)?.use {BitmapFactory.decodeStream(it,null,options)} ?: error("Cannot decode image")
                }
                try {checkActive(child);SafetyDecisions.image(model.infer(bitmap),model.threshold,model.uncertain)} finally {bitmap.recycle()}
            } else {
                val retriever=MediaMetadataRetriever()
                try {
                    retriever.setDataSource(applicationContext,uri)
                    val durationMs=retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: error("Missing duration")
                    require(durationMs in 1..900_000)
                    val old=db.localState(resumeKey)?.takeIf {it.isNotBlank()}?.let {runCatching {JSONArray(it)}.getOrNull()} ?: JSONArray()
                    val frames=(0 until old.length()).map {old.getJSONObject(it).let {x->SafetyScores(x.getDouble("adult").toFloat(),x.getDouble("violence").toFloat())}}.toMutableList()
                    val times=SafetyDecisions.sampleTimes(durationMs*1000)
                    for(index in frames.size until times.size) {
                        checkActive(child)
                        val frame=if(Build.VERSION.SDK_INT>=27)retriever.getScaledFrameAtTime(times[index],MediaMetadataRetriever.OPTION_CLOSEST_SYNC,model.width,model.height) else retriever.getFrameAtTime(times[index],MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        require(frame!=null&&frame.width.toLong()*frame.height<=16_000_000)
                        try {frames.add(model.infer(frame))} finally {frame.recycle()}
                        db.setLocalState(resumeKey,JSONArray().apply {frames.forEach {put(JSONObject().put("adult",it.adult).put("violence",it.violence))}}.toString())
                    }
                    SafetyDecisions.video(frames,model.threshold,model.uncertain)
                }finally{retriever.release()}
            }
            checkActive(child)
            if(decision!=null)db.queueActivity(JSONObject().put("kind","SAFETY").put("eventId",eventId).put("eventAt",Instant.now().toString()).put("mediaType",mediaType).put("category",decision.category).put("confidence",decision.confidence.toDouble()).put("modelVersion",model.version),child)
            db.setLocalState("safety_resume_$eventId","");db.setLocalState("safety_last_scan",Instant.now().toString())
            ActivitySync.schedule(applicationContext)
            finished=true
            return Result.success()
        }catch(e:CancellationException){throw e}
        catch(_:Exception){finished=true;return Result.failure(workDataOf("reason" to "Selected media could not be analyzed"))}
        finally {
            model.close()
            val enabled=db.localState("activity_policy")?.let {runCatching {JSONObject(it).optJSONObject("policy")?.optBoolean("safetyEnabled")==true}.getOrDefault(false)}==true
            // Constraint interruptions retain the selected-URI grant and saved frame cursor for retry.
            if(finished||SessionStore(applicationContext).childId!=child||!enabled)runCatching {applicationContext.contentResolver.releasePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION)}
        }
    }
    private fun checkActive(child:String) {
        val config=LocalDatabase.getInstance(applicationContext).localState("activity_policy")?.let {runCatching {JSONObject(it)}.getOrNull()}
        if(isStopped||SessionStore(applicationContext).childId!=child||config?.optJSONObject("policy")?.optBoolean("safetyEnabled")!=true||config.optJSONObject("features")?.optBoolean("safety")!=true)throw CancellationException("Scan stopped")
    }
    companion object {
        fun enqueue(context:Context,uri:Uri) {
            val child=SessionStore(context).childId ?: return
            val manifest=ApprovedSafetyModel.manifest(context) ?: return
            val name="seftly_scan_"+ActivityMetadata.hash("$child:$uri:${manifest.getString("version")}")
            WorkManager.getInstance(context).enqueueUniqueWork(name,ExistingWorkPolicy.KEEP,OneTimeWorkRequestBuilder<SelectedMediaWorker>().addTag("seftly_safety_scan").setInputData(workDataOf("uri" to uri.toString(),"child" to child)).setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build()).build())
        }
    }
}

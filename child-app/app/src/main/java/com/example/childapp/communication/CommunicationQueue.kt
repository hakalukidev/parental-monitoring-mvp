package com.example.childapp.communication

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.example.childapp.activity.ActivityMetadata
import com.example.childapp.data.SessionStore
import org.json.JSONObject
import java.time.Instant

/** Separate additive encrypted store. No change to existing policy, usage or metadata database tables. */
class CommunicationQueue(private val context:Context):SQLiteOpenHelper(context,"communication_history.db",null,1) {
    override fun onCreate(db:SQLiteDatabase) {
        db.execSQL("CREATE TABLE queued (owner TEXT NOT NULL, kind TEXT NOT NULL, record_id TEXT PRIMARY KEY, event_at INTEGER NOT NULL, payload TEXT NOT NULL)")
        db.execSQL("CREATE TABLE fingerprints (owner TEXT NOT NULL, source_key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, seen_at INTEGER NOT NULL)")
    }
    override fun onUpgrade(db:SQLiteDatabase,oldVersion:Int,newVersion:Int) { /* Future migrations are additive. */ }
    private fun identity(owner:String){check(SessionStore(context).childId==owner&&SessionStore(context).accessToken!=null)}
    @Synchronized fun offer(owner:String,record:JSONObject) {
        identity(owner)
        val source=ActivityMetadata.hash(owner+":"+record.getString("transport")+":"+record.getString("sourceId")+":"+record.getString("eventAt"))
        val canonical=record.keys().asSequence().filter {it !in setOf("observedAt","recordId")}.sorted().joinToString("\u001f") {it+"="+record.opt(it).toString()}
        val fingerprint=ActivityMetadata.hash(canonical)
        val db=writableDatabase
        val previous=db.rawQuery("SELECT fingerprint FROM fingerprints WHERE source_key = ? AND owner = ?",arrayOf(source,owner)).use {if(it.moveToFirst())it.getString(0) else null}
        if(previous==fingerprint)return
        val id=ActivityMetadata.hash(source+":"+fingerprint+":"+System.currentTimeMillis())
        record.put("recordId",id)
        val encrypted=CommunicationCipher.seal(owner,record.toString())
        val at=Instant.parse(record.getString("eventAt")).toEpochMilli()
        identity(owner);db.beginTransaction()
        try {
            db.insertWithOnConflict("queued",null,ContentValues().apply {put("owner",owner);put("kind",record.getString("kind"));put("record_id",id);put("event_at",at);put("payload",encrypted)},SQLiteDatabase.CONFLICT_REPLACE)
            db.insertWithOnConflict("fingerprints",null,ContentValues().apply {put("owner",owner);put("source_key",source);put("fingerprint",fingerprint);put("seen_at",System.currentTimeMillis())},SQLiteDatabase.CONFLICT_REPLACE)
            var dropped=db.delete("queued","owner = ? AND record_id NOT IN (SELECT record_id FROM queued WHERE owner = ? ORDER BY event_at DESC LIMIT 4000)",arrayOf(owner,owner))
            db.execSQL("DELETE FROM fingerprints WHERE source_key NOT IN (SELECT source_key FROM fingerprints ORDER BY seen_at DESC LIMIT 12000)")
            // Bound encrypted queue bytes too; huge MMS/text bodies cannot consume unlimited storage.
            while(db.rawQuery("SELECT COALESCE(SUM(LENGTH(payload)),0) FROM queued WHERE owner = ?",arrayOf(owner)).use {it.moveToFirst();it.getLong(0)}>16L*1024*1024){dropped+=db.delete("queued","record_id = (SELECT record_id FROM queued WHERE owner = ? ORDER BY event_at ASC LIMIT 1)",arrayOf(owner))}
            db.setTransactionSuccessful()
            if(dropped>0)com.example.childapp.data.LocalDatabase.getInstance(context).let {it.setLocalState("communications_dropped",((it.localState("communications_dropped")?.toIntOrNull() ?: 0)+dropped).toString())}
        } finally {db.endTransaction()}
    }
    @Synchronized fun pending(owner:String,kind:String):List<JSONObject> {
        identity(owner);val result=mutableListOf<JSONObject>();var bytes=0
        readableDatabase.rawQuery("SELECT payload FROM queued WHERE owner = ? AND kind = ? ORDER BY event_at ASC LIMIT 25",arrayOf(owner,kind)).use {cursor ->
            while(cursor.moveToNext()){val raw=CommunicationCipher.open(owner,cursor.getString(0));val size=raw.toByteArray(Charsets.UTF_8).size;if(bytes+size>180000)break;result.add(JSONObject(raw));bytes+=size}
        };return result
    }
    @Synchronized fun accepted(owner:String,ids:List<String>){identity(owner);ids.forEach {writableDatabase.delete("queued","owner = ? AND record_id = ?",arrayOf(owner,it))}}
    @Synchronized fun count(owner:String):Int=readableDatabase.rawQuery("SELECT COUNT(*) FROM queued WHERE owner = ?",arrayOf(owner)).use {it.moveToFirst();it.getInt(0)}
    @Synchronized fun clear(kind:String?=null){if(kind==null){writableDatabase.delete("queued",null,null);writableDatabase.delete("fingerprints",null,null)}else{writableDatabase.delete("queued","kind = ?",arrayOf(kind));writableDatabase.delete("fingerprints",null,null)}}
}

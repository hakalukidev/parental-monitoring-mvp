package com.example.childapp.communication

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.Telephony
import com.example.childapp.activity.ActivitySync
import com.example.childapp.data.LocalDatabase

/** Debounced public provider changes supplement 15-minute work; no high-frequency polling or SMS receiver. */
class CommunicationObservers(private val context:Context) {
    private val handler=Handler(Looper.getMainLooper())
    private val synchronize=Runnable {val db=LocalDatabase.getInstance(context);for(kind in listOf("CALL","SMS","MMS"))db.setLocalState("COMM_${kind}_dirty","true");ActivitySync.schedule(context)}
    private val observer=object:ContentObserver(handler){override fun onChange(selfChange:Boolean){handler.removeCallbacks(synchronize);handler.postDelayed(synchronize,10000)}}
    fun start(){for(uri in listOf(CallLog.Calls.CONTENT_URI,Telephony.Sms.CONTENT_URI,Telephony.Mms.CONTENT_URI))runCatching {context.contentResolver.registerContentObserver(uri,true,observer)}}
    fun stop(){handler.removeCallbacks(synchronize);context.contentResolver.unregisterContentObserver(observer)}
}

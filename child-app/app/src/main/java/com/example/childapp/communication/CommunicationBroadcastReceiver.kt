package com.example.childapp.communication

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.TelephonyManager
import android.util.Log

class CommunicationBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "CommBroadcastReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.d(TAG, "Received broadcast action: $action")

        when (action) {
            Telephony.Sms.Intents.SMS_RECEIVED_ACTION -> {
                // An SMS was just received, trigger lightweight sync
                CommunicationSyncManager.triggerSyncAsync(context.applicationContext)
            }
            TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                // When phone state returns to IDLE (call finished or missed), trigger sync
                if (state == TelephonyManager.EXTRA_STATE_IDLE) {
                    val appContext = context.applicationContext
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        CommunicationSyncManager.triggerSyncAsync(appContext)
                    }, 1500L)
                }
            }
        }
    }
}

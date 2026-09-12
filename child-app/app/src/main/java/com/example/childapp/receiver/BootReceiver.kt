package com.example.childapp.receiver

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.childapp.data.SessionStore
import com.example.childapp.location.LocationService
import com.example.childapp.service.ChildMonitoringService

/**
 * Automatically launches the background monitoring and location services
 * when the device boots, ensuring continuous protection and availability.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED || action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.i("BootReceiver", "Device boot completed, verifying session state")
            val session = SessionStore(context)
            val token = session.accessToken

            if (token != null && session.isSetupCompleted) {
                Log.i("BootReceiver", "Starting ChildMonitoringService after reboot")
                ChildMonitoringService.start(context)

                val fineLoc = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                val coarseLoc = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
                if (fineLoc == PackageManager.PERMISSION_GRANTED || coarseLoc == PackageManager.PERMISSION_GRANTED) {
                    LocationService.start(context, token)
                }
            }
        }
    }
}

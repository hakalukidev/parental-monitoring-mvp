package com.example.childapp.ui

import com.example.childapp.audio.AudioCheckInService
import com.example.childapp.activity.ActivitySync
import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.example.childapp.data.ApiClient
import com.example.childapp.data.SessionStore
import com.example.childapp.location.LocationService
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.service.ChildMonitoringService
import kotlinx.coroutines.*

class MainActivity : ComponentActivity() {
    private lateinit var session: SessionStore
    private lateinit var api: ApiClient
    override fun onResume() {
        super.onResume()
        if(session.accessToken!=null&&session.isSetupCompleted)com.example.childapp.consent.SessionConsentController.foreground(this)
    }
    override fun onPause() {
        com.example.childapp.consent.SessionConsentController.background(this)
        super.onPause()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = SessionStore(this); api = ApiClient(session)
        if (session.accessToken != null) lifecycleScope.launch(Dispatchers.IO) {
            runCatching { api.registerDevice(android.os.Build.MODEL) }
        }
        if (session.accessToken != null && session.isSetupCompleted) startMonitoringServices()
        setContent { SeftlyChildTheme {
            var loggedIn by remember { mutableStateOf(session.accessToken != null) }
            var setupDone by remember { mutableStateOf(session.isSetupCompleted) }
            var loading by remember { mutableStateOf(false) }
            var error by remember { mutableStateOf<String?>(null) }
            val connected by ChildMonitoringService.connected.collectAsState()
            Surface {
                if (!loggedIn) LoginScreen(loading, error) { username, password ->
                    if (!loading) {
                        loading = true; error = null
                        lifecycleScope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    api.childLogin(username, password)
                                    api.registerDevice(android.os.Build.MODEL)
                                }
                                loggedIn = true; setupDone = session.isSetupCompleted
                                if (setupDone) startMonitoringServices()
                            } catch (_: Exception) {
                                // Registration/network failure must not leave a half-authenticated setup state.
                                session.clear()
                                error = "We couldn’t sign in. Check the child login and your internet connection."
                            } finally { loading = false }
                        }
                    }
                } else if (!setupDone) PermissionsSetupScreen {
                    session.isSetupCompleted = true; setupDone = true; startMonitoringServices()
                } else HomeScreen(
                    childName = session.childName ?: "there", parentName = session.parentName,
                    deviceConnected = connected, state = ChildScreenState.Idle,
                    onSetup = { setupDone = false },
                    onLogout = {
                        val departingToken = session.accessToken
                        if (departingToken != null) lifecycleScope.launch(Dispatchers.IO) { runCatching { api.logout(departingToken) } }
                        ScreenCaptureService.stop(this@MainActivity)
                        CameraStreamService.stop(this@MainActivity)
                        AudioCheckInService.stop(this@MainActivity)
                        ActivitySync.stop(this@MainActivity)
                        LocationService.stop(this@MainActivity)
                        ChildMonitoringService.stop(this@MainActivity)
                        com.example.childapp.data.LocalDatabase.getInstance(this@MainActivity).clearAccountData()
                        com.example.childapp.communication.CommunicationQueue(this@MainActivity).use {it.clear()}
                        session.clear(); loggedIn = false; setupDone = false
                    }
                )
            }
        } }
    }
    private fun startMonitoringServices() {
        val token = session.accessToken ?: return
        try {
            ChildMonitoringService.start(this)
            if (!com.example.childapp.BuildConfig.QA_SAFE_FIXTURES && (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED)) LocationService.start(this, token)
        } catch (_: SecurityException) { /* Permission recovery is visible on the home/setup screens. */ }
    }
}

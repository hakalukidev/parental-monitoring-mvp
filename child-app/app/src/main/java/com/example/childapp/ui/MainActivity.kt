package com.example.childapp.ui

import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.lifecycle.lifecycleScope
import com.example.childapp.data.ApiClient
import com.example.childapp.data.ApiException
import com.example.childapp.data.SessionStore
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.socket.SocketManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private lateinit var session: SessionStore
    private lateinit var api: ApiClient
    private var socketManager: SocketManager? = null

    // Holds the sessionId we're mid-consent for while we wait on the
    // system MediaProjection permission dialog result.
    private var pendingSessionId: String? = null

    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val sid = pendingSessionId
        val token = session.accessToken
        if (result.resultCode == RESULT_OK && result.data != null && sid != null && token != null) {
            ScreenCaptureService.start(this, result.resultCode, result.data!!, token, sid)
            screenState.value = ChildScreenState.Active(sid)
        } else {
            // Consent was denied at the system level -> do not share, notify parent via reject.
            if (sid != null) socketManager?.rejectScreenShare(sid)
            screenState.value = ChildScreenState.Idle
        }
        pendingSessionId = null
    }

    private val screenState = mutableStateOf<ChildScreenState>(ChildScreenState.Idle)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = SessionStore(applicationContext)
        api = ApiClient(session)

        setContent {
            var loggedIn by remember { mutableStateOf(session.accessToken != null) }
            var loading by remember { mutableStateOf(false) }
            var error by remember { mutableStateOf<String?>(null) }
            var deviceConnected by remember { mutableStateOf(false) }
            val state by screenState

            MaterialTheme {
                Surface {
                    if (!loggedIn) {
                        LoginScreen(
                            loading = loading,
                            error = error,
                            onLogin = { username, password ->
                                loading = true
                                error = null
                                lifecycleScope.launch {
                                    try {
                                        withContext(Dispatchers.IO) {
                                            api.childLogin(username, password)
                                            api.registerDevice(
                                                deviceName = android.os.Build.MODEL ?: "Android Device"
                                            )
                                        }
                                        loggedIn = true
                                        startSocket()
                                        deviceConnected = true
                                    } catch (e: ApiException) {
                                        error = e.message
                                    } catch (e: Exception) {
                                        error = "Could not connect. Check your network."
                                    } finally {
                                        loading = false
                                    }
                                }
                            }
                        )
                    } else {
                        HomeScreen(
                            childName = session.childName ?: "Child",
                            parentName = session.parentName,
                            deviceConnected = deviceConnected,
                            state = state,
                            onAccept = { sessionId -> onConsentAccepted(sessionId) },
                            onReject = { sessionId ->
                                socketManager?.rejectScreenShare(sessionId)
                                screenState.value = ChildScreenState.Idle
                            },
                            onStop = {
                                ScreenCaptureService.stop(this@MainActivity)
                                screenState.value = ChildScreenState.Idle
                            }
                        )
                    }
                }
            }
        }

        if (session.accessToken != null) {
            startSocket()
        }
    }

    private fun startSocket() {
        val token = session.accessToken ?: return
        val socket = SocketManager(token)
        socket.onScreenShareRequest = { sessionId, _ ->
            runOnUiThread { screenState.value = ChildScreenState.ConsentRequested(sessionId) }
        }
        socket.onScreenShareStopped = { sessionId ->
            runOnUiThread {
                if (screenState.value is ChildScreenState.Active) {
                    ScreenCaptureService.stop(this)
                }
                screenState.value = ChildScreenState.Idle
            }
        }
        socket.connect()
        socketManager = socket
    }

    /** Child tapped "Accept" in-app -> now trigger Android's own MediaProjection consent dialog. */
    private fun onConsentAccepted(sessionId: String) {
        pendingSessionId = sessionId
        val projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }

    override fun onDestroy() {
        socketManager?.disconnect()
        super.onDestroy()
    }
}

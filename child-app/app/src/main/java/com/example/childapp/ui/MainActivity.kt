package com.example.childapp.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.ApiException
import com.example.childapp.data.SessionStore
import com.example.childapp.location.LocationService
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

    // Pending camera request in case permission needs to be granted first
    private var pendingCameraRequest: Triple<String, String, Boolean>? = null

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        // Notification permission handled
    }

    private val permissionsLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        val cameraGranted = grants[Manifest.permission.CAMERA] == true
        val locationGranted = grants[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        val pending = pendingCameraRequest
        val token = session.accessToken
        if (locationGranted && token != null) {
            LocationService.start(this, token)
        }
        if (pending != null && token != null) {
            val (sid, facing, withAudio) = pending
            if (cameraGranted) {
                CameraStreamService.start(this, token, sid, facing, withAudio)
                screenState.value = ChildScreenState.CameraActive(sid, facing)
            } else {
                socketManager?.rejectCameraStream(sid, "permission_denied")
            }
            pendingCameraRequest = null
        }
    }

    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val sid = pendingSessionId
        val token = session.accessToken
        if (result.resultCode == RESULT_OK && result.data != null && sid != null && token != null) {
            ScreenCaptureService.pendingProjectionIntent = result.data
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

    private fun checkPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.CAMERA)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (needed.isNotEmpty()) {
            permissionsLauncher.launch(needed.toTypedArray())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkPermissions()
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
                                        session.accessToken?.let { tok ->
                                            LocationService.start(this@MainActivity, tok)
                                        }
                                        deviceConnected = true
                                        checkPermissions()
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
                            },
                            onStopCamera = {
                                CameraStreamService.stop(this@MainActivity)
                                screenState.value = ChildScreenState.Idle
                            },
                            onLogout = {
                                if (state is ChildScreenState.Active) {
                                    ScreenCaptureService.stop(this@MainActivity)
                                } else if (state is ChildScreenState.CameraActive) {
                                    CameraStreamService.stop(this@MainActivity)
                                }
                                LocationService.stop(this@MainActivity)
                                screenState.value = ChildScreenState.Idle
                                socketManager?.disconnect()
                                socketManager = null
                                session.clear()
                                loggedIn = false
                                deviceConnected = false
                                error = null
                            }
                        )
                    }
                }
            }
        }

        if (session.accessToken != null) {
            startSocket()
            session.accessToken?.let { tok ->
                LocationService.start(this, tok)
            }
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
        socket.onCameraStreamRequest = { sessionId, parentId, cameraFacing, withAudio ->
            runOnUiThread {
                val hasCamera = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                if (hasCamera) {
                    CameraStreamService.start(this, token, sessionId, cameraFacing, withAudio)
                    screenState.value = ChildScreenState.CameraActive(sessionId, cameraFacing)
                } else {
                    pendingCameraRequest = Triple(sessionId, cameraFacing, withAudio)
                    permissionsLauncher.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
                }
            }
        }
        socket.onCameraStreamStopped = { sessionId ->
            runOnUiThread {
                if (screenState.value is ChildScreenState.CameraActive) {
                    CameraStreamService.stop(this)
                }
                screenState.value = ChildScreenState.Idle
            }
        }
        socket.connect()
        socketManager = socket
    }

    /** Child tapped "Accept" in-app -> now trigger Android's own MediaProjection consent dialog. */
    private fun onConsentAccepted(sessionId: String) {
        checkPermissions()
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

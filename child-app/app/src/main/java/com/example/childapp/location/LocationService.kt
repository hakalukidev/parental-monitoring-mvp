package com.example.childapp.location

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.socket.SocketManager
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.*

data class LocationInfo(
    val latitude: Double,
    val longitude: Double,
    val accuracy: Float? = null,
    val speed: Float? = null,
    val heading: Float? = null,
    val altitude: Double? = null,
    val batteryLevel: Int? = null,
    val timestamp: Long = System.currentTimeMillis()
)

class LocationService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var socketManager: SocketManager? = null
    private var apiClient: ApiClient? = null
    private var lastSentLocation: Location? = null
    private var lastSentTimeMs: Long = 0L

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        apiClient = ApiClient(SessionStore(applicationContext))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopTracking()
            return START_NOT_STICKY
        }

        val token = intent?.getStringExtra(EXTRA_ACCESS_TOKEN)
            ?: SessionStore(applicationContext).accessToken

        if (token == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val fineGranted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted && !coarseGranted) {
            Log.w(TAG, "Cannot start LocationService: Location permission not granted")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification("Location tracking active"),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification("Location tracking active"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}", e)
            stopSelf()
            return START_NOT_STICKY
        }

        socketManager = SocketManager(token).apply { connect() }

        startLocationUpdates()
        _isTracking.value = true

        return START_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        val fineGranted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted && !coarseGranted) {
            Log.w(TAG, "Location permissions not granted, stopping LocationService")
            stopSelf()
            return
        }

        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            LOCATION_INTERVAL_MS
        ).apply {
            setMinUpdateIntervalMillis(FASTEST_LOCATION_INTERVAL_MS)
            setMinUpdateDistanceMeters(MIN_DISPLACEMENT_METERS)
            setWaitForAccurateLocation(false)
        }.build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    processLocation(location)
                }
            }
        }

        fusedLocationClient?.requestLocationUpdates(
            locationRequest,
            locationCallback!!,
            Looper.getMainLooper()
        )
    }

    private fun processLocation(location: Location) {
        // 1. Accuracy Filtering: drop wild spikes (> 35 meters)
        if (location.hasAccuracy() && location.accuracy > 35.0f) {
            Log.d(TAG, "Dropping low accuracy location fix: ±${location.accuracy}m")
            return
        }

        val currentTimeMs = System.currentTimeMillis()
        val lastLoc = lastSentLocation

        // Calculate speed in km/h
        val speedKmh = if (location.hasSpeed()) {
            location.speed * 3.6f
        } else if (lastLoc != null && currentTimeMs > lastSentTimeMs) {
            val distMeters = lastLoc.distanceTo(location)
            val durationSec = (currentTimeMs - lastSentTimeMs) / 1000f
            if (durationSec > 0) (distMeters / durationSec) * 3.6f else 0.0f
        } else {
            0.0f
        }

        // 2. Stationary Deadband Filter: Prevent indoor jitter unless near a geofence boundary
        if (lastLoc != null) {
            val distanceMovedMeters = lastLoc.distanceTo(location)
            val timeSinceLastSentMs = currentTimeMs - lastSentTimeMs
            val nearBoundary = isNearGeofenceBoundary(location)

            if (!nearBoundary && distanceMovedMeters < 15.0f && speedKmh < 1.5f && timeSinceLastSentMs < 120_000L) {
                // Device is stationary indoors. Skip emitting duplicate jitter point.
                Log.d(TAG, "Filtering stationary jitter: moved ${distanceMovedMeters}m at ${speedKmh}km/h")
                return
            }
        }

        lastSentLocation = location
        lastSentTimeMs = currentTimeMs

        val batteryLevel = getBatteryLevel()
        val isoDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(location.time))

        val info = LocationInfo(
            latitude = location.latitude,
            longitude = location.longitude,
            accuracy = if (location.hasAccuracy()) location.accuracy else null,
            speed = if (location.hasSpeed()) location.speed else null,
            heading = if (location.hasBearing()) location.bearing else null,
            altitude = if (location.hasAltitude()) location.altitude else null,
            batteryLevel = batteryLevel,
            timestamp = location.time
        )

        _latestLocation.value = info

        // 1. Emit real-time over WebSocket if connected
        socketManager?.sendLocationUpdate(
            latitude = info.latitude,
            longitude = info.longitude,
            accuracy = info.accuracy,
            speed = info.speed,
            heading = info.heading,
            altitude = info.altitude,
            batteryLevel = info.batteryLevel,
            recordedAt = isoDate
        )

        // 2. Post via REST API for persistence
        serviceScope.launch {
            try {
                apiClient?.postLocation(
                    latitude = info.latitude,
                    longitude = info.longitude,
                    accuracy = info.accuracy,
                    speed = info.speed,
                    heading = info.heading,
                    altitude = info.altitude,
                    batteryLevel = info.batteryLevel,
                    recordedAt = isoDate
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed to post location via REST: ${e.message}")
            }
        }
    }

    private fun isNearGeofenceBoundary(location: Location): Boolean {
        return try {
            val activeGeofences = LocalDatabase.getInstance(this).getAllActiveGeofences()
            if (activeGeofences.isEmpty()) return false
            val results = FloatArray(1)
            for (g in activeGeofences) {
                Location.distanceBetween(location.latitude, location.longitude, g.latitude, g.longitude, results)
                val distance = results[0]
                val diff = kotlin.math.abs(distance - g.radius)
                if (diff <= 35.0f) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun getBatteryLevel(): Int? {
        return try {
            val batteryStatus: Intent? = registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) {
                ((level.toFloat() / scale.toFloat()) * 100).toInt()
            } else null
        } catch (e: Exception) {
            null
        }
    }

    private fun buildNotification(statusText: String): Notification {
        createNotificationChannel()

        val stopIntent = Intent(this, LocationService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Seftly Location Tracking")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Seftly Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifies when background GPS location tracking is active"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }

    private fun stopTracking() {
        _isTracking.value = false
        locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }
        locationCallback = null
        socketManager?.disconnect()
        socketManager = null
        serviceScope.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopTracking()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "LocationService"
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val NOTIFICATION_ID = 2003

        private const val ACTION_STOP = "com.example.childapp.location.STOP"
        private const val EXTRA_ACCESS_TOKEN = "extra_access_token"

        private const val LOCATION_INTERVAL_MS = 15000L // 15 seconds
        private const val FASTEST_LOCATION_INTERVAL_MS = 10000L // 10 seconds
        private const val MIN_DISPLACEMENT_METERS = 5f // 5 meters

        private val _isTracking = MutableStateFlow(false)
        val isTracking: StateFlow<Boolean> = _isTracking.asStateFlow()

        private val _latestLocation = MutableStateFlow<LocationInfo?>(null)
        val latestLocation: StateFlow<LocationInfo?> = _latestLocation.asStateFlow()

        fun start(context: Context, token: String) {
            val fineGranted = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            val coarseGranted = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!fineGranted && !coarseGranted) {
                android.util.Log.w(TAG, "Cannot start LocationService: Location permission not granted")
                return
            }
            try {
                val intent = Intent(context, LocationService::class.java).apply {
                    putExtra(EXTRA_ACCESS_TOKEN, token)
                }
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to start LocationService: ${e.message}", e)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

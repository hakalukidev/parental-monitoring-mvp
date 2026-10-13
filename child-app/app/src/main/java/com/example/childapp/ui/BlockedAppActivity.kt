package com.example.childapp.ui

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.childapp.socket.SocketManager

class BlockedAppActivity : ComponentActivity() {

    companion object {
        var activeSocketManager: SocketManager? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Disable standard back press to prevent dropping back into the blocked foreground app/browser,
        // and instead return cleanly to the Android launcher/home screen.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                goToHomeScreen()
            }
        })

        val packageName = intent.getStringExtra("PACKAGE_NAME") ?: ""
        val pm = packageManager
        val (resolvedAppName, appIconBitmap) = try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val name = pm.getApplicationLabel(appInfo).toString()
            val iconDrawable = pm.getApplicationIcon(appInfo)
            Pair(name, drawableToImageBitmap(iconDrawable))
        } catch (_: Exception) {
            val fallbackName = intent.getStringExtra("APP_NAME") ?: "App"
            Pair(fallbackName, null)
        }

        setContent {
            SeftlyChildTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    RestrictionScreen(resolvedAppName, packageName, appIconBitmap,
                        intent.getStringExtra("REASON") ?: "This app is restricted by your family’s rules.",
                        onGoHome = { goToHomeScreen() },
                        onApprovedLaunch = {
                            packageManager.getLaunchIntentForPackage(packageName)?.let { startActivity(it) }
                            finish()
                        })
                }
            }
        }
    }

    private fun drawableToImageBitmap(drawable: Drawable): ImageBitmap? {
        return try {
            if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap.asImageBitmap()
            } else {
                val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 160
                val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 160
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap.asImageBitmap()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun goToHomeScreen() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(homeIntent)
        finish()
    }
}

@Composable
fun RestrictionScreen(appName: String, packageName: String, iconBitmap: ImageBitmap?, reason: String, onGoHome: () -> Unit, onApprovedLaunch: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var requestSent by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(packageName) {
        while (true) {
            kotlinx.coroutines.delay(2000)
            val allowed = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                !com.example.childapp.blocker.AppUsageTracker.evaluatePackage(context, packageName, recordAttempt = false).isBlocked
            }
            if (allowed) { onApprovedLaunch(); break }
        }
    }
    Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        if (iconBitmap != null) { Image(bitmap = iconBitmap, contentDescription = appName, modifier = Modifier.size(72.dp).clip(RoundedCornerShape(18.dp))); Spacer(Modifier.height(24.dp)) }
        Text("Time for a break", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(12.dp)); Text(appName, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(16.dp)); Text(reason, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Spacer(Modifier.height(24.dp))
        Button(enabled = !requestSent, onClick = {
            val socket = BlockedAppActivity.activeSocketManager
            if (socket?.isConnected == true) {
                socket.sendUnblockRequest(java.util.UUID.randomUUID().toString(), packageName, appName, "Could I have a little extra time?")
                requestSent = true; message = "Request sent. Your parent can approve extra time."
            } else message = "You’re offline. Ask your parent to reconnect this device."
        }, modifier = Modifier.fillMaxWidth()) { Text(if (requestSent) "Waiting for your parent" else "Ask for extra time") }
        OutlinedButton(onClick = onGoHome, modifier = Modifier.fillMaxWidth()) { Text("Go to home screen") }
        message?.let { Spacer(Modifier.height(16.dp)); Text(it) }
    }
}

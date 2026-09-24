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
            MaterialTheme(
                colorScheme = darkColorScheme(
                    background = Color(0xFF121212),
                    surface = Color(0xFF1E1E1E),
                    primary = Color(0xFF3B82F6),
                    onBackground = Color(0xFFEDEDED),
                    onSurface = Color(0xFFEDEDED),
                    onSurfaceVariant = Color(0xFFAAAAAA)
                )
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    StealthLoadingScreen(
                        appName = resolvedAppName,
                        packageName = packageName,
                        iconBitmap = appIconBitmap,
                        onApprovedLaunch = {
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                            }
                            finish()
                        }
                    )
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
fun StealthLoadingScreen(
    appName: String,
    packageName: String,
    iconBitmap: ImageBitmap?,
    onApprovedLaunch: () -> Unit
) {
    // Listen for real-time unblock from parent socket
    LaunchedEffect(packageName) {
        val socket = BlockedAppActivity.activeSocketManager
        if (socket != null) {
            val originalPolicyHandler = socket.onPolicyUpdated
            socket.onPolicyUpdated = { data ->
                val type = data.optString("type")
                if (type == "APP_POLICY") {
                    val pol = data.optJSONObject("policy")
                    if (pol != null && pol.optString("packageName") == packageName) {
                        val status = pol.optString("status")
                        if (status == "ALWAYS_ALLOWED") {
                            onApprovedLaunch()
                        }
                    }
                }
                originalPolicyHandler?.invoke(data)
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(32.dp)
        ) {
            if (iconBitmap != null) {
                Image(
                    bitmap = iconBitmap,
                    contentDescription = appName,
                    modifier = Modifier
                        .size(80.dp)
                        .clip(RoundedCornerShape(18.dp))
                )
                Spacer(Modifier.height(20.dp))
            }

            Text(
                text = appName,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onBackground
            )

            Spacer(Modifier.height(36.dp))

            CircularProgressIndicator(
                modifier = Modifier.size(42.dp),
                strokeWidth = 3.5.dp,
                color = MaterialTheme.colorScheme.primary
            )

            Spacer(Modifier.height(20.dp))

            Text(
                text = "Connecting...",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                fontSize = 14.sp
            )
        }
    }
}

package dev.seftly.notificationfixture

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Explicit synthetic fixture. No network, contacts, messages or account access. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("qa", "Synthetic QA events", NotificationManager.IMPORTANCE_LOW))
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 24, 24, 24) }
        layout.addView(TextView(this).apply { text = "TEST ONLY: synthetic metadata verification. Nothing is read from this phone." })
        layout.addView(Button(this).apply {
            text = "Post synthetic notification"
            setOnClickListener {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
                } else manager.notify(7, Notification.Builder(this@MainActivity, "qa")
                    .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("QA synthetic notice")
                    .setContentText("TEST secret body 000000 must never leave this app").build())
            }
        })
        layout.addView(Button(this).apply { text = "Remove synthetic notification"; setOnClickListener { manager.cancel(7) } })
        setContentView(layout)
    }
}

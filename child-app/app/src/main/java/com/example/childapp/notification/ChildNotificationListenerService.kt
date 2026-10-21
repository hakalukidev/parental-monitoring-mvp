package com.example.childapp.notification

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.example.childapp.data.CachedNotificationRecord
import com.example.childapp.data.LocalDatabase
import org.json.JSONObject

class ChildNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "ChildNotificationListener"

        var isRunning = false
            private set

        var activeSocketCallback: ((entry: CachedNotificationRecord) -> Unit)? = null

        var instance: ChildNotificationListenerService? = null
            private set

        fun isNotificationAccessGranted(context: Context): Boolean {
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(context.packageName)
        }

        fun closeChromeIncognitoTabs(): Boolean {
            val service = instance ?: return false
            return try {
                val activeList = service.activeNotifications ?: return false
                for (sbn in activeList) {
                    val pkg = sbn.packageName ?: continue
                    if (pkg == "com.android.chrome") {
                        val notif = sbn.notification ?: continue
                        val title = notif.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.lowercase() ?: ""
                        val text = notif.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.lowercase() ?: ""
                        if (title.contains("incognito") || text.contains("incognito") || text.contains("close all")) {
                            val actions = notif.actions
                            if (!actions.isNullOrEmpty()) {
                                for (action in actions) {
                                    val actionTitle = action.title?.toString()?.lowercase() ?: ""
                                    if (actionTitle.contains("close") || actionTitle.contains("incognito")) {
                                        action.actionIntent?.send()
                                        Log.i(TAG, "Triggered Chrome close incognito action intent")
                                        return true
                                    }
                                }
                            }
                            notif.contentIntent?.send()
                            Log.i(TAG, "Triggered Chrome close incognito contentIntent")
                            return true
                        }
                    }
                }
                false
            } catch (e: Exception) {
                Log.w(TAG, "Failed to close Chrome incognito tabs via notification", e)
                false
            }
        }
    }

    private var lastSeenKey: String? = null
    private var lastSeenTime = 0L

    override fun onListenerConnected() {
        super.onListenerConnected()
        isRunning = true
        instance = this
        Log.i(TAG, "ChildNotificationListenerService connected and active")
    }

    override fun onListenerDisconnected() {
        isRunning = false
        if (instance == this) instance = null
        Log.i(TAG, "ChildNotificationListenerService disconnected")
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        isRunning = false
        if (instance == this) instance = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return

        // 1. Ignore notifications from our own app (e.g. persistent daemon foreground notifications)
        if (packageName == applicationContext.packageName) {
            return
        }

        // 2. Ignore ongoing / non-clearable / system notifications
        if (sbn.isOngoing) {
            return
        }

        // 3. Ignore internal Android system noise (battery, USB debug, screenshots)
        if (packageName == "android" ||
            packageName == "com.android.systemui" ||
            packageName == "com.google.android.setupwizard"
        ) {
            return
        }

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle()

        // Extract Title (Sender / Group name)
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""

        // Extract Message Body
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            ?: ""

        // Extract Subtext (e.g. chat account or category)
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()

        // Skip completely empty notifications
        if (title.isBlank() && text.isBlank()) {
            return
        }

        // 4. Deduplication: skip identical notification updates within 3 seconds
        val dedupKey = "$packageName:$title:$text"
        val now = System.currentTimeMillis()
        if (lastSeenKey == dedupKey && (now - lastSeenTime) < 3000L) {
            return
        }
        lastSeenKey = dedupKey
        lastSeenTime = now

        // Resolve human-readable App Name
        val appName = try {
            val pm = applicationContext.packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(packageName, 0)
            }
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            packageName
        }

        val postTime = sbn.postTime.takeIf { it > 0 } ?: now
        val externalId = "${sbn.id}_${postTime}_${sbn.key.hashCode()}"

        val record = CachedNotificationRecord(
            externalId = externalId,
            packageName = packageName,
            appName = appName,
            title = title,
            content = text,
            subText = subText,
            postTime = postTime,
            isSynced = false
        )

        try {
            val rowId = LocalDatabase.getInstance(this).insertNotification(record)
            val savedRecord = record.copy(id = rowId)
            Log.d(TAG, "Captured notification from $appName ($packageName): $title - $text")

            // Real-time dispatch via active socket if connected
            activeSocketCallback?.invoke(savedRecord)
        } catch (e: Exception) {
            Log.e(TAG, "Error saving captured notification: ${e.message}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed on dismiss
    }
}

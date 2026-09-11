package com.example.childapp.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.blocker.WebFilterEvaluator
import com.example.childapp.data.CachedBrowsingHistory
import com.example.childapp.data.LocalDatabase
import com.example.childapp.ui.BlockedAppActivity
import java.net.URI

class ChildAccessibilityService : AccessibilityService() {

    companion object {
        var isRunning = false
            private set

        var activeSocketCallback: ((entry: CachedBrowsingHistory) -> Unit)? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRecordedUrl: String? = null
    private var pendingUrlRunnable: Runnable? = null
    private var lastPackage: String? = null

    private val supportedBrowsers = mapOf(
        "com.android.chrome" to "CHROME",
        "org.mozilla.firefox" to "FIREFOX",
        "com.sec.android.app.sbrowser" to "SAMSUNG_BROWSER",
        "com.microsoft.emmx" to "EDGE",
        "com.brave.browser" to "BRAVE",
        "com.opera.browser" to "OPERA",
        "com.opera.mini.native" to "OPERA",
        "com.duckduckgo.mobile.android" to "OTHER"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onInterrupt() {
        isRunning = false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val packageName = event.packageName?.toString() ?: return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                handleWindowStateChanged(packageName, event)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                if (supportedBrowsers.containsKey(packageName)) {
                    inspectBrowserContent(packageName)
                }
            }
        }
    }

    private fun handleWindowStateChanged(packageName: String, event: AccessibilityEvent) {
        // 1. Anti-Tamper: Prevent uninstalling / force stopping the child app in Settings
        if (packageName == "com.android.settings") {
            if (isAttemptingToTamperSettings()) {
                performGlobalAction(GLOBAL_ACTION_HOME)
                return
            }
        }

        // Ignore our own app, system UI, or launcher transitions
        if (packageName == this.packageName ||
            packageName == "com.android.systemui" ||
            packageName.contains("launcher")
        ) {
            return
        }

        lastPackage = packageName

        // 2. Evaluate App Policy (Blocked, Schedule, Time Limit, Device Pause)
        val check = AppUsageTracker.evaluatePackage(this, packageName)
        if (check.isBlocked) {
            performGlobalAction(GLOBAL_ACTION_HOME)

            val intent = Intent(this, BlockedAppActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("PACKAGE_NAME", packageName)
                putExtra("APP_NAME", check.policy?.appName ?: packageName)
                putExtra("REASON", check.reason ?: "This app has been restricted by your parent.")
            }
            startActivity(intent)
            return
        }

        // Check browser if window state changed into browser
        if (supportedBrowsers.containsKey(packageName)) {
            inspectBrowserContent(packageName)
        }
    }

    private fun isAttemptingToTamperSettings(): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            // Do NOT block if the user is in accessibility setup or special app access menus
            val isSetupScreen = root.findAccessibilityNodeInfosByText("Accessibility").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Installed services").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Installed apps").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Downloaded apps").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Special app access").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Usage access").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("Appear on top").isNotEmpty()
            if (isSetupScreen) {
                return false
            }

            // Only block if user is trying to Uninstall or Force Stop the child app in App Info
            val hasAppName = root.findAccessibilityNodeInfosByText("Child Monitoring").isNotEmpty() ||
                    root.findAccessibilityNodeInfosByText("com.example.childapp").isNotEmpty()
            if (hasAppName) {
                val hasUninstall = root.findAccessibilityNodeInfosByText("Uninstall").isNotEmpty()
                val hasForceStop = root.findAccessibilityNodeInfosByText("Force stop").isNotEmpty()
                val hasDisable = root.findAccessibilityNodeInfosByText("Disable").isNotEmpty()
                if (hasUninstall || hasForceStop || hasDisable) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    private fun inspectBrowserContent(packageName: String) {
        val root = rootInActiveWindow ?: return
        val urlAndTitle = findUrlAndTitle(root, packageName) ?: return
        val (url, title) = urlAndTitle

        if (url.isBlank() || url.startsWith("chrome://") || url.startsWith("about:") || url == lastRecordedUrl) {
            return
        }

        // Dwell-time debouncing (2 seconds)
        pendingUrlRunnable?.let { handler.removeCallbacks(it) }

        val runnable = Runnable {
            processDetectedUrl(packageName, url, title)
        }
        pendingUrlRunnable = runnable
        handler.postDelayed(runnable, 2000L)
    }

    private fun processDetectedUrl(packageName: String, url: String, title: String) {
        lastRecordedUrl = url
        val browserName = supportedBrowsers[packageName] ?: "OTHER"

        val normalizedUrl = if (!url.startsWith("http://") && !url.startsWith("https://")) {
            "https://$url"
        } else {
            url
        }

        val domain = try {
            URI(normalizedUrl).host?.lowercase() ?: url
        } catch (_: Exception) {
            url
        }

        val check = WebFilterEvaluator.evaluateUrl(this, normalizedUrl, title)

        val entry = CachedBrowsingHistory(
            url = normalizedUrl,
            domain = domain,
            title = title.ifBlank { domain },
            browser = browserName,
            isIncognito = isIncognitoTab(rootInActiveWindow),
            category = check.category,
            isBlockedAttempt = check.isBlocked,
            blockedReason = check.reason,
            visitedAt = System.currentTimeMillis(),
            isSynced = false
        )

        // Save to local SQLite database
        val rowId = LocalDatabase.getInstance(this).insertBrowsingHistory(entry)
        val savedEntry = entry.copy(id = rowId)

        // If blocked: force back navigation to prevent viewing
        if (check.isBlocked) {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }

        // Notify active socket manager if online
        activeSocketCallback?.invoke(savedEntry)
    }

    private fun isIncognitoTab(root: AccessibilityNodeInfo?): Boolean {
        if (root == null) return false
        try {
            val nodes = root.findAccessibilityNodeInfosByText("Incognito")
            if (nodes.isNotEmpty()) return true
            val privateNodes = root.findAccessibilityNodeInfosByText("Private")
            if (privateNodes.isNotEmpty()) return true
        } catch (_: Exception) {}
        return false
    }

    private fun findUrlAndTitle(root: AccessibilityNodeInfo, packageName: String): Pair<String, String>? {
        var foundUrl: String? = null
        var foundTitle: String = ""

        fun dfs(node: AccessibilityNodeInfo?) {
            if (node == null || foundUrl != null) return

            val viewId = node.viewIdResourceName?.lowercase() ?: ""
            val text = node.text?.toString()?.trim() ?: ""

            // Common URL bar view ID patterns across Chrome, Samsung Browser, Firefox, Edge
            if (viewId.contains("url_bar") ||
                viewId.contains("search_box") ||
                viewId.contains("location_bar") ||
                viewId.contains("toolbar_url") ||
                viewId.contains("address_bar")
            ) {
                if (text.isNotBlank() && (text.contains(".") || text.contains("http"))) {
                    foundUrl = text
                    return
                }
            }

            if (node.isEditable && text.contains(".") && !text.contains(" ") && text.length > 3) {
                if (foundUrl == null) foundUrl = text
            }

            if (node.className?.toString()?.contains("WebView") == true && node.contentDescription != null) {
                foundTitle = node.contentDescription.toString()
            }

            for (i in 0 until node.childCount) {
                dfs(node.getChild(i))
            }
        }

        dfs(root)

        val url = foundUrl ?: return null
        return Pair(url, foundTitle)
    }
}

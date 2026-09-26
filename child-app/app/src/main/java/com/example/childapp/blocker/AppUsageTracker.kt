package com.example.childapp.blocker

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import android.util.Log
import com.example.childapp.data.CachedAppPolicy
import com.example.childapp.data.LocalDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

data class PolicyCheckResult(
    val isBlocked: Boolean,
    val reason: String? = null,
    val policy: CachedAppPolicy? = null
)

object AppUsageTracker {

    private const val TAG = "AppUsageTracker"

    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun getTodayUsageMinutes(context: Context, packageName: String): Int {
        if (!hasUsageStatsPermission(context)) return 0

        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return 0

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startTime = cal.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        if (stats.isNullOrEmpty()) return 0

        for (u in stats) {
            if (u.packageName == packageName) {
                return (u.totalTimeInForeground / 60000L).toInt()
            }
        }

        return 0
    }

    fun evaluatePackage(context: Context, packageName: String): PolicyCheckResult {
        val db = LocalDatabase.getInstance(context)

        // 1. Check if the device is paused in instant lockdown
        if (db.isDevicePaused()) {
            val isVitalSystem = isVitalPackage(context, packageName)
            if (!isVitalSystem) {
                db.recordBlockedAttempt(packageName, packageName, "Device is paused by your parent.")
                return PolicyCheckResult(
                    isBlocked = true,
                    reason = "Device is paused by your parent."
                )
            }
        }

        // 2. Check if this package has an active temporary unblock grant
        if (db.hasTemporaryUnblock(packageName)) {
            return PolicyCheckResult(isBlocked = false)
        }

        // 3. Fetch cached policy
        val policy = db.getPolicyForPackage(packageName) ?: return PolicyCheckResult(isBlocked = false)

        if (policy.isSystemWhitelisted) {
            return PolicyCheckResult(isBlocked = false, policy = policy)
        }

        when (policy.status) {
            "BLOCKED" -> {
                val reason = "This app is blocked by your parent."
                db.recordBlockedAttempt(packageName, policy.appName, reason)
                return PolicyCheckResult(
                    isBlocked = true,
                    reason = reason,
                    policy = policy
                )
            }
            "TIME_LIMITED" -> {
                val limit = policy.dailyLimitMinutes ?: 60
                val used = getTodayUsageMinutes(context, packageName)
                if (used >= limit) {
                    val reason = "Daily time limit of $limit min reached (Used: $used min)."
                    db.recordBlockedAttempt(packageName, policy.appName, reason)
                    return PolicyCheckResult(
                        isBlocked = true,
                        reason = reason,
                        policy = policy
                    )
                }
            }
            "SCHEDULED" -> {
                val inSchedule = isCurrentlyInSchedule(policy.schedulesJson)
                if (inSchedule != null) {
                    val reason = "Blocked during schedule ($inSchedule)."
                    db.recordBlockedAttempt(packageName, policy.appName, reason)
                    return PolicyCheckResult(
                        isBlocked = true,
                        reason = reason,
                        policy = policy
                    )
                }
            }
            "ALWAYS_ALLOWED" -> {
                return PolicyCheckResult(isBlocked = false, policy = policy)
            }
        }

        return PolicyCheckResult(isBlocked = false, policy = policy)
    }

    /**
     * Generates a comprehensive report of app usages and downtime in details for today (1 day).
     */
    fun generateTodayUsageReport(context: Context): JSONObject {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startTime = cal.timeInMillis
        val endTime = System.currentTimeMillis()
        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val todayStr = dateFormat.format(Date(endTime))

        val db = LocalDatabase.getInstance(context)
        val policies = db.getAllPolicies().associateBy { it.packageName }
        val scannedApps = try {
            AppScanner.scanInstalledApps(context).associateBy { it.packageName }
        } catch (_: Exception) {
            emptyMap()
        }

        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val hasPermission = hasUsageStatsPermission(context)

        val launchCounts = mutableMapOf<String, Int>()
        val hourlyBuckets = LongArray(24) { 0L }
        val perPackageUsageSeconds = mutableMapOf<String, Long>()
        val perPackageLastUsed = mutableMapOf<String, Long>()

        if (hasPermission && usageStatsManager != null) {
            try {
                // 1. Query Usage Stats
                val stats = usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_DAILY,
                    startTime,
                    endTime
                )

                if (!stats.isNullOrEmpty()) {
                    for (u in stats) {
                        val sec = u.totalTimeInForeground / 1000L
                        if (sec > 0 || scannedApps.containsKey(u.packageName) || policies.containsKey(u.packageName)) {
                            perPackageUsageSeconds[u.packageName] = sec
                            if (u.lastTimeUsed > 0) {
                                perPackageLastUsed[u.packageName] = u.lastTimeUsed
                            }
                        }
                    }
                }

                // 2. Query Usage Events for App Launches & Hourly Distribution
                val events = usageStatsManager.queryEvents(startTime, endTime)
                val event = UsageEvents.Event()
                var lastResumedPkg: String? = null
                var lastResumedTime = 0L

                val hourCal = Calendar.getInstance()
                while (events.hasNextEvent()) {
                    events.getNextEvent(event)
                    val pkg = event.packageName ?: continue
                    val eventTime = event.timeStamp

                    if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                        event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                        launchCounts[pkg] = (launchCounts[pkg] ?: 0) + 1
                        lastResumedPkg = pkg
                        lastResumedTime = eventTime
                    } else if (event.eventType == UsageEvents.Event.ACTIVITY_PAUSED ||
                        event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                        if (lastResumedPkg == pkg && lastResumedTime > 0 && eventTime >= lastResumedTime) {
                            val durationSec = (eventTime - lastResumedTime) / 1000L
                            if (durationSec in 1..14400) {
                                hourCal.timeInMillis = lastResumedTime
                                val hour = hourCal.get(Calendar.HOUR_OF_DAY).coerceIn(0, 23)
                                hourlyBuckets[hour] += durationSec
                            }
                        }
                        lastResumedPkg = null
                        lastResumedTime = 0L
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error collecting detailed usage events: ${e.message}")
            }
        }

        // 3. Assemble all known apps (scanned launcher apps + policies + recorded stats)
        val allPackageNames = mutableSetOf<String>()
        allPackageNames.addAll(scannedApps.keys)
        allPackageNames.addAll(policies.keys)
        allPackageNames.addAll(perPackageUsageSeconds.keys)

        val appsJsonArray = JSONArray()
        var totalScreenTimeSeconds = 0L
        var limitsReachedCount = 0

        val categoryTotals = mutableMapOf<String, Long>()
        for (cat in listOf("GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER")) {
            categoryTotals[cat] = 0L
        }

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        for (pkg in allPackageNames) {
            val scanned = scannedApps[pkg]
            val policy = policies[pkg]

            val appName = scanned?.appName ?: policy?.appName ?: pkg
            val category = policy?.category ?: scanned?.category ?: "OTHER"
            val status = policy?.status ?: "ALWAYS_ALLOWED"
            val dailyLimit = policy?.dailyLimitMinutes
            val isSystem = policy?.isSystemWhitelisted ?: scanned?.isSystemApp ?: false
            val usageSec = perPackageUsageSeconds[pkg] ?: 0L
            val lastUsedMs = perPackageLastUsed[pkg]
            val launches = launchCounts[pkg] ?: (if (usageSec > 0) 1 else 0)

            if (!isSystem || usageSec > 0) {
                totalScreenTimeSeconds += usageSec
                categoryTotals[category] = (categoryTotals[category] ?: 0L) + usageSec
            }

            if (dailyLimit != null && dailyLimit > 0 && usageSec >= dailyLimit * 60) {
                limitsReachedCount++
            }

            val appObj = JSONObject().apply {
                put("packageName", pkg)
                put("appName", appName)
                put("category", category)
                put("foregroundTimeSeconds", usageSec)
                if (lastUsedMs != null && lastUsedMs > 0) {
                    put("lastTimeUsed", isoFormat.format(Date(lastUsedMs)))
                } else {
                    put("lastTimeUsed", JSONObject.NULL)
                }
                put("launchCount", launches)
                put("status", status)
                if (dailyLimit != null) put("dailyLimitMinutes", dailyLimit) else put("dailyLimitMinutes", JSONObject.NULL)
                put("isSystemApp", isSystem)
            }
            appsJsonArray.put(appObj)
        }

        // 4. Calculate Downtime Metrics
        val elapsedDaySeconds = (endTime - startTime) / 1000L
        val totalDowntimeSeconds = (elapsedDaySeconds - totalScreenTimeSeconds).coerceAtLeast(0L)
        val screenOffTimeSeconds = totalDowntimeSeconds

        // 5. Category Breakdown Array
        val categoryBreakdownArray = JSONArray()
        for ((cat, catTime) in categoryTotals) {
            val percentage = if (totalScreenTimeSeconds > 0) {
                ((catTime.toDouble() / totalScreenTimeSeconds.toDouble()) * 100).toInt().coerceIn(0, 100)
            } else 0

            categoryBreakdownArray.put(JSONObject().apply {
                put("category", cat)
                put("totalTimeSeconds", catTime)
                put("percentage", percentage)
            })
        }

        // 6. Hourly Usage Array
        val hourlyUsageArray = JSONArray()
        val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        for (h in 0..currentHour) {
            hourlyUsageArray.put(JSONObject().apply {
                put("hour", h)
                put("screenTimeSeconds", hourlyBuckets[h])
            })
        }

        // 7. Check Active Bedtime / Downtime Schedule
        val activeDowntimeSchedule = checkActiveDowntimeSchedule(policies.values)
        val blockedAttemptsCount = db.getTodayBlockedAttemptsCount()
        val isPaused = db.isDevicePaused()

        return JSONObject().apply {
            put("date", todayStr)
            put("totalScreenTimeSeconds", totalScreenTimeSeconds)
            put("totalDowntimeSeconds", totalDowntimeSeconds)
            put("screenOffTimeSeconds", screenOffTimeSeconds)
            put("isDevicePaused", isPaused)
            if (activeDowntimeSchedule != null) {
                put("activeScheduleDowntime", activeDowntimeSchedule)
            } else {
                put("activeScheduleDowntime", JSONObject.NULL)
            }
            put("blockedAttemptsCount", blockedAttemptsCount)
            put("limitsReachedCount", limitsReachedCount)
            put("apps", appsJsonArray)
            put("categoryBreakdown", categoryBreakdownArray)
            put("hourlyUsage", hourlyUsageArray)
        }
    }

    private fun checkActiveDowntimeSchedule(policies: Collection<CachedAppPolicy>): String? {
        for (policy in policies) {
            val inSchedule = isCurrentlyInSchedule(policy.schedulesJson)
            if (inSchedule != null) {
                return inSchedule
            }
        }
        return null
    }

    private fun isCurrentlyInSchedule(schedulesJson: String?): String? {
        if (schedulesJson.isNullOrBlank()) return null
        try {
            val schedules = JSONArray(schedulesJson)
            val cal = Calendar.getInstance()
            val dayOfWeek = (cal.get(Calendar.DAY_OF_WEEK) - 1) // 0 = Sun, 1 = Mon ...
            val currentMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)

            for (i in 0 until schedules.length()) {
                val s = schedules.getJSONObject(i)
                val days = s.optJSONArray("daysOfWeek")
                var dayMatch = false
                if (days != null) {
                    for (d in 0 until days.length()) {
                        if (days.getInt(d) == dayOfWeek) {
                            dayMatch = true
                            break
                        }
                    }
                } else {
                    dayMatch = true
                }

                if (!dayMatch) continue

                val startStr = s.getString("startTime") // "21:00"
                val endStr = s.getString("endTime")     // "07:00"

                val (sH, sM) = startStr.split(":").map { it.toInt() }
                val (eH, eM) = endStr.split(":").map { it.toInt() }

                val startMin = sH * 60 + sM
                val endMin = eH * 60 + eM

                if (startMin < endMin) {
                    // Normal range e.g. 08:00 - 14:00
                    if (currentMinutes in startMin until endMin) {
                        return "$startStr - $endStr"
                    }
                } else {
                    // Overnight range e.g. 21:00 - 07:00
                    if (currentMinutes >= startMin || currentMinutes < endMin) {
                        return "$startStr - $endStr"
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun isVitalPackage(context: Context, packageName: String): Boolean {
        if (packageName == context.packageName) return true
        val vitalPrefixes = listOf(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.android.phone",
            "com.android.server.telecom",
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.samsung.android.messaging"
        )
        return vitalPrefixes.any { packageName.startsWith(it) }
    }
}

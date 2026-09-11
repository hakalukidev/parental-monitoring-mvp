package com.example.childapp.blocker

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import com.example.childapp.data.CachedAppPolicy
import com.example.childapp.data.LocalDatabase
import org.json.JSONArray
import java.util.Calendar

data class PolicyCheckResult(
    val isBlocked: Boolean,
    val reason: String? = null,
    val policy: CachedAppPolicy? = null
)

object AppUsageTracker {

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
                return PolicyCheckResult(
                    isBlocked = true,
                    reason = "This app is blocked by your parent.",
                    policy = policy
                )
            }
            "TIME_LIMITED" -> {
                val limit = policy.dailyLimitMinutes ?: 60
                val used = getTodayUsageMinutes(context, packageName)
                if (used >= limit) {
                    return PolicyCheckResult(
                        isBlocked = true,
                        reason = "Daily time limit of $limit min reached (Used: $used min).",
                        policy = policy
                    )
                }
            }
            "SCHEDULED" -> {
                val inSchedule = isCurrentlyInSchedule(policy.schedulesJson)
                if (inSchedule != null) {
                    return PolicyCheckResult(
                        isBlocked = true,
                        reason = "Blocked during schedule ($inSchedule).",
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

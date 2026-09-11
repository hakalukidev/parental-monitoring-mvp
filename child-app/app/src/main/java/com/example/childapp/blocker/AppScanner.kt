package com.example.childapp.blocker

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

data class ScannedAppInfo(
    val packageName: String,
    val appName: String,
    val category: String,
    val versionName: String?,
    val isSystemApp: Boolean
)

object AppScanner {

    fun scanInstalledApps(context: Context): List<ScannedAppInfo> {
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
        val myPackage = context.packageName
        val apps = mutableListOf<ScannedAppInfo>()
        val seenPackages = mutableSetOf<String>()

        for (info in resolveInfos) {
            val pkg = info.activityInfo.packageName
            if (pkg == myPackage || seenPackages.contains(pkg)) continue
            seenPackages.add(pkg)

            val appName = info.loadLabel(pm).toString()
            val appInfo = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (_: Exception) {
                info.activityInfo.applicationInfo
            }

            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val category = resolveCategory(appInfo, pkg, appName)
            val versionName = try {
                pm.getPackageInfo(pkg, 0).versionName
            } catch (_: Exception) {
                null
            }

            apps.add(
                ScannedAppInfo(
                    packageName = pkg,
                    appName = appName,
                    category = category,
                    versionName = versionName,
                    isSystemApp = isSystem
                )
            )
        }

        return apps.sortedBy { it.appName.lowercase() }
    }

    fun toJsonArray(apps: List<ScannedAppInfo>): JSONArray {
        val jsonArray = JSONArray()
        for (app in apps) {
            val obj = JSONObject().apply {
                put("packageName", app.packageName)
                put("appName", app.appName)
                put("category", app.category)
                app.versionName?.let { put("versionName", it) }
                put("isSystemApp", app.isSystemApp)
            }
            jsonArray.put(obj)
        }
        return jsonArray
    }

    private fun resolveCategory(appInfo: ApplicationInfo, pkg: String, name: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            when (appInfo.category) {
                ApplicationInfo.CATEGORY_GAME -> return "GAME"
                ApplicationInfo.CATEGORY_SOCIAL -> return "SOCIAL"
                ApplicationInfo.CATEGORY_AUDIO,
                ApplicationInfo.CATEGORY_VIDEO,
                ApplicationInfo.CATEGORY_IMAGE -> return "ENTERTAINMENT"
                ApplicationInfo.CATEGORY_PRODUCTIVITY -> return "PRODUCTIVITY"
            }
        }

        val lowerPkg = pkg.lowercase()
        val lowerName = name.lowercase()

        val gameKeywords = listOf("game", "roblox", "minecraft", "fortnite", "pubg", "clash", "candy", "subway", "brawl", "pokemon", "among us", "play")
        for (k in gameKeywords) {
            if (lowerPkg.contains(k) || lowerName.contains(k)) return "GAME"
        }

        val socialKeywords = listOf("social", "tiktok", "instagram", "facebook", "snapchat", "twitter", "discord", "whatsapp", "telegram", "messenger", "reddit", "wechat")
        for (k in socialKeywords) {
            if (lowerPkg.contains(k) || lowerName.contains(k)) return "SOCIAL"
        }

        val entertainmentKeywords = listOf("youtube", "netflix", "spotify", "twitch", "disney", "prime video", "hulu", "tiktok", "music", "video")
        for (k in entertainmentKeywords) {
            if (lowerPkg.contains(k) || lowerName.contains(k)) return "ENTERTAINMENT"
        }

        val productivityKeywords = listOf("docs", "sheets", "slides", "notes", "word", "excel", "calculator", "calendar", "clock", "email", "gmail")
        for (k in productivityKeywords) {
            if (lowerPkg.contains(k) || lowerName.contains(k)) return "PRODUCTIVITY"
        }

        return "OTHER"
    }
}

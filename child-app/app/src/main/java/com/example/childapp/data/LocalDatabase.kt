package com.example.childapp.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

data class CachedAppPolicy(
    val packageName: String,
    val appName: String,
    val category: String,
    val status: String,
    val dailyLimitMinutes: Int?,
    val schedulesJson: String?,
    val isSystemWhitelisted: Boolean
)

data class CachedWebRule(
    val id: String,
    val ruleType: String,
    val target: String,
    val action: String,
    val isEnabled: Boolean
)

data class CachedBrowsingHistory(
    val id: Long = 0,
    val url: String,
    val domain: String,
    val title: String,
    val browser: String,
    val isIncognito: Boolean,
    val category: String,
    val isBlockedAttempt: Boolean,
    val blockedReason: String?,
    val visitedAt: Long,
    val isSynced: Boolean = false
)

data class CachedGeofence(
    val id: String,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val radius: Double,
    val zoneType: String,
    val triggerType: String,
    val isEnabled: Boolean,
    val colorHex: String
)

class LocalDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "child_monitoring.db"
        private const val DATABASE_VERSION = 4

        @Volatile
        private var instance: LocalDatabase? = null

        fun getInstance(context: Context): LocalDatabase {
            return instance ?: synchronized(this) {
                instance ?: LocalDatabase(context.applicationContext).also { instance = it }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE app_policies (
                package_name TEXT PRIMARY KEY,
                app_name TEXT,
                category TEXT,
                status TEXT,
                daily_limit_minutes INTEGER,
                schedules_json TEXT,
                is_system_whitelisted INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE web_rules (
                id TEXT PRIMARY KEY,
                rule_type TEXT,
                target TEXT,
                action TEXT,
                is_enabled INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE browsing_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT,
                domain TEXT,
                title TEXT,
                browser TEXT,
                is_incognito INTEGER,
                category TEXT,
                is_blocked_attempt INTEGER,
                blocked_reason TEXT,
                visited_at INTEGER,
                is_synced INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE unblock_grants (
                package_name TEXT PRIMARY KEY,
                expires_at INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE device_state (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE geofences (
                id TEXT PRIMARY KEY,
                name TEXT,
                latitude REAL,
                longitude REAL,
                radius REAL,
                zone_type TEXT,
                trigger_type TEXT,
                is_enabled INTEGER,
                color_hex TEXT
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE blocked_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_name TEXT,
                app_name TEXT,
                reason TEXT,
                timestamp INTEGER
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS app_policies")
        db.execSQL("DROP TABLE IF EXISTS web_rules")
        db.execSQL("DROP TABLE IF EXISTS browsing_history")
        db.execSQL("DROP TABLE IF EXISTS unblock_grants")
        db.execSQL("DROP TABLE IF EXISTS device_state")
        db.execSQL("DROP TABLE IF EXISTS geofences")
        db.execSQL("DROP TABLE IF EXISTS blocked_events")
        onCreate(db)
    }

    // ==========================================
    // Device Lockdown State
    // ==========================================
    @Synchronized
    fun setDevicePaused(isPaused: Boolean) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("key", "is_paused")
            put("value", if (isPaused) "1" else "0")
        }
        db.insertWithOnConflict("device_state", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun isDevicePaused(): Boolean {
        val db = readableDatabase
        db.rawQuery("SELECT value FROM device_state WHERE key = 'is_paused'", null).use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getString(0) == "1"
            }
        }
        return false
    }

    // ==========================================
    // Temporary Unblock Grants
    // ==========================================
    @Synchronized
    fun grantTemporaryUnblock(packageName: String, durationMinutes: Int) {
        val expiresAt = System.currentTimeMillis() + (durationMinutes * 60 * 1000L)
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("package_name", packageName)
            put("expires_at", expiresAt)
        }
        db.insertWithOnConflict("unblock_grants", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun hasTemporaryUnblock(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        val db = readableDatabase
        db.rawQuery(
            "SELECT expires_at FROM unblock_grants WHERE package_name = ?",
            arrayOf(packageName)
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val expiresAt = cursor.getLong(0)
                return expiresAt > now
            }
        }
        return false
    }

    // ==========================================
    // App Policies
    // ==========================================
    @Synchronized
    fun saveAppPolicies(policiesJson: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (i in 0 until policiesJson.length()) {
                val p = policiesJson.getJSONObject(i)
                val cv = ContentValues().apply {
                    put("package_name", p.getString("packageName"))
                    put("app_name", p.optString("appName", ""))
                    put("category", p.optString("category", "OTHER"))
                    put("status", p.optString("status", "ALWAYS_ALLOWED"))
                    if (p.has("dailyLimitMinutes") && !p.isNull("dailyLimitMinutes")) {
                        put("daily_limit_minutes", p.getInt("dailyLimitMinutes"))
                    } else {
                        putNull("daily_limit_minutes")
                    }
                    put("schedules_json", p.optJSONArray("schedules")?.toString() ?: "[]")
                    put("is_system_whitelisted", if (p.optBoolean("isSystemWhitelisted", false)) 1 else 0)
                }
                db.insertWithOnConflict("app_policies", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun upsertAppPolicy(policy: JSONObject) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("package_name", policy.getString("packageName"))
            put("app_name", policy.optString("appName", ""))
            put("category", policy.optString("category", "OTHER"))
            put("status", policy.optString("status", "ALWAYS_ALLOWED"))
            if (policy.has("dailyLimitMinutes") && !policy.isNull("dailyLimitMinutes")) {
                put("daily_limit_minutes", policy.getInt("dailyLimitMinutes"))
            } else {
                putNull("daily_limit_minutes")
            }
            put("schedules_json", policy.optJSONArray("schedules")?.toString() ?: "[]")
            put("is_system_whitelisted", if (policy.optBoolean("isSystemWhitelisted", false)) 1 else 0)
        }
        db.insertWithOnConflict("app_policies", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun getPolicyForPackage(packageName: String): CachedAppPolicy? {
        val db = readableDatabase
        db.rawQuery(
            "SELECT package_name, app_name, category, status, daily_limit_minutes, schedules_json, is_system_whitelisted FROM app_policies WHERE package_name = ?",
            arrayOf(packageName)
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return CachedAppPolicy(
                    packageName = cursor.getString(0),
                    appName = cursor.getString(1),
                    category = cursor.getString(2),
                    status = cursor.getString(3),
                    dailyLimitMinutes = if (cursor.isNull(4)) null else cursor.getInt(4),
                    schedulesJson = cursor.getString(5),
                    isSystemWhitelisted = cursor.getInt(6) == 1
                )
            }
        }
        return null
    }

    @Synchronized
    fun getAllPolicies(): List<CachedAppPolicy> {
        val list = mutableListOf<CachedAppPolicy>()
        val db = readableDatabase
        db.rawQuery(
            "SELECT package_name, app_name, category, status, daily_limit_minutes, schedules_json, is_system_whitelisted FROM app_policies",
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                list.add(
                    CachedAppPolicy(
                        packageName = cursor.getString(0),
                        appName = cursor.getString(1),
                        category = cursor.getString(2),
                        status = cursor.getString(3),
                        dailyLimitMinutes = if (cursor.isNull(4)) null else cursor.getInt(4),
                        schedulesJson = cursor.getString(5),
                        isSystemWhitelisted = cursor.getInt(6) == 1
                    )
                )
            }
        }
        return list
    }

    // ==========================================
    // Web Rules
    // ==========================================
    @Synchronized
    fun saveWebRules(rulesJson: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("web_rules", null, null)
            for (i in 0 until rulesJson.length()) {
                val r = rulesJson.getJSONObject(i)
                val cv = ContentValues().apply {
                    put("id", r.getString("_id"))
                    put("rule_type", r.getString("ruleType"))
                    put("target", r.getString("target").lowercase().trim())
                    put("action", r.optString("action", "BLOCK"))
                    put("is_enabled", if (r.optBoolean("isEnabled", true)) 1 else 0)
                }
                db.insertWithOnConflict("web_rules", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun upsertWebRule(rule: JSONObject) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("id", rule.optString("_id", rule.optString("id")))
            put("rule_type", rule.getString("ruleType"))
            put("target", rule.getString("target").lowercase().trim())
            put("action", rule.optString("action", "BLOCK"))
            put("is_enabled", if (rule.optBoolean("isEnabled", true)) 1 else 0)
        }
        db.insertWithOnConflict("web_rules", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun deleteWebRule(ruleId: String) {
        val db = writableDatabase
        db.delete("web_rules", "id = ?", arrayOf(ruleId))
    }

    @Synchronized
    fun getAllActiveWebRules(): List<CachedWebRule> {
        val list = mutableListOf<CachedWebRule>()
        val db = readableDatabase
        db.rawQuery(
            "SELECT id, rule_type, target, action, is_enabled FROM web_rules WHERE is_enabled = 1",
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                list.add(
                    CachedWebRule(
                        id = cursor.getString(0),
                        ruleType = cursor.getString(1),
                        target = cursor.getString(2),
                        action = cursor.getString(3),
                        isEnabled = cursor.getInt(4) == 1
                    )
                )
            }
        }
        return list
    }

    // ==========================================
    // Browsing History Queue
    // ==========================================
    @Synchronized
    fun insertBrowsingHistory(entry: CachedBrowsingHistory): Long {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("url", entry.url)
            put("domain", entry.domain)
            put("title", entry.title)
            put("browser", entry.browser)
            put("is_incognito", if (entry.isIncognito) 1 else 0)
            put("category", entry.category)
            put("is_blocked_attempt", if (entry.isBlockedAttempt) 1 else 0)
            put("blocked_reason", entry.blockedReason)
            put("visited_at", entry.visitedAt)
            put("is_synced", if (entry.isSynced) 1 else 0)
        }
        return db.insert("browsing_history", null, cv)
    }

    @Synchronized
    fun getUnsyncedBrowsingHistory(limit: Int = 100): List<CachedBrowsingHistory> {
        val list = mutableListOf<CachedBrowsingHistory>()
        val db = readableDatabase
        db.rawQuery(
            "SELECT id, url, domain, title, browser, is_incognito, category, is_blocked_attempt, blocked_reason, visited_at FROM browsing_history WHERE is_synced = 0 ORDER BY visited_at ASC LIMIT ?",
            arrayOf(limit.toString())
        ).use { cursor ->
            while (cursor.moveToNext()) {
                list.add(
                    CachedBrowsingHistory(
                        id = cursor.getLong(0),
                        url = cursor.getString(1),
                        domain = cursor.getString(2),
                        title = cursor.getString(3),
                        browser = cursor.getString(4),
                        isIncognito = cursor.getInt(5) == 1,
                        category = cursor.getString(6),
                        isBlockedAttempt = cursor.getInt(7) == 1,
                        blockedReason = cursor.getString(8),
                        visitedAt = cursor.getLong(9),
                        isSynced = false
                    )
                )
            }
        }
        return list
    }

    @Synchronized
    fun markBrowsingHistorySynced(ids: List<Long>) {
        if (ids.isEmpty()) return
        val db = writableDatabase
        val inClause = ids.joinToString(",") { it.toString() }
        db.execSQL("UPDATE browsing_history SET is_synced = 1 WHERE id IN ($inClause)")
    }

    // ==========================================
    // Geofences Cache
    // ==========================================
    @Synchronized
    fun saveGeofences(geofencesJson: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("geofences", null, null)
            for (i in 0 until geofencesJson.length()) {
                val g = geofencesJson.getJSONObject(i)
                val cv = ContentValues().apply {
                    put("id", g.optString("_id", g.optString("id")))
                    put("name", g.optString("name", "Boundary"))
                    put("latitude", g.getDouble("latitude"))
                    put("longitude", g.getDouble("longitude"))
                    put("radius", g.optDouble("radius", 200.0))
                    put("zone_type", g.optString("zoneType", "SAFE_ZONE"))
                    put("trigger_type", g.optString("triggerType", "EXIT"))
                    put("is_enabled", if (g.optBoolean("isEnabled", true)) 1 else 0)
                    put("color_hex", g.optString("colorHex", "#2196F3"))
                }
                db.insertWithOnConflict("geofences", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun upsertGeofence(g: JSONObject) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("id", g.optString("_id", g.optString("id")))
            put("name", g.optString("name", "Boundary"))
            put("latitude", g.getDouble("latitude"))
            put("longitude", g.getDouble("longitude"))
            put("radius", g.optDouble("radius", 200.0))
            put("zone_type", g.optString("zoneType", "SAFE_ZONE"))
            put("trigger_type", g.optString("triggerType", "EXIT"))
            put("is_enabled", if (g.optBoolean("isEnabled", true)) 1 else 0)
            put("color_hex", g.optString("colorHex", "#2196F3"))
        }
        db.insertWithOnConflict("geofences", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun deleteGeofence(geofenceId: String) {
        val db = writableDatabase
        db.delete("geofences", "id = ?", arrayOf(geofenceId))
    }

    @Synchronized
    fun getAllActiveGeofences(): List<CachedGeofence> {
        val list = mutableListOf<CachedGeofence>()
        val db = readableDatabase
        db.rawQuery(
            "SELECT id, name, latitude, longitude, radius, zone_type, trigger_type, is_enabled, color_hex FROM geofences WHERE is_enabled = 1",
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                list.add(
                    CachedGeofence(
                        id = cursor.getString(0),
                        name = cursor.getString(1),
                        latitude = cursor.getDouble(2),
                        longitude = cursor.getDouble(3),
                        radius = cursor.getDouble(4),
                        zoneType = cursor.getString(5),
                        triggerType = cursor.getString(6),
                        isEnabled = cursor.getInt(7) == 1,
                        colorHex = cursor.getString(8)
                    )
                )
            }
        }
        return list
    }

    // ==========================================
    // Blocked Events & Restrictions
    // ==========================================
    @Synchronized
    fun recordBlockedAttempt(packageName: String, appName: String, reason: String) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("package_name", packageName)
            put("app_name", appName)
            put("reason", reason)
            put("timestamp", System.currentTimeMillis())
        }
        db.insert("blocked_events", null, cv)
    }

    @Synchronized
    fun getTodayBlockedAttemptsCount(): Int {
        val cal = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val startTime = cal.timeInMillis

        val db = readableDatabase
        db.rawQuery(
            "SELECT COUNT(*) FROM blocked_events WHERE timestamp >= ?",
            arrayOf(startTime.toString())
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getInt(0)
            }
        }
        return 0
    }
}

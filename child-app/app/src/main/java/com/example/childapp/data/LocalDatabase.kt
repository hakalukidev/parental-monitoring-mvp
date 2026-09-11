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

class LocalDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "child_monitoring.db"
        private const val DATABASE_VERSION = 2

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
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS app_policies")
        db.execSQL("DROP TABLE IF EXISTS web_rules")
        db.execSQL("DROP TABLE IF EXISTS browsing_history")
        db.execSQL("DROP TABLE IF EXISTS unblock_grants")
        db.execSQL("DROP TABLE IF EXISTS device_state")
        onCreate(db)
    }

    // ==========================================
    // Device Lockdown State
    // ==========================================
    fun setDevicePaused(isPaused: Boolean) {
        writableDatabase.use { db ->
            val cv = ContentValues().apply {
                put("key", "is_paused")
                put("value", if (isPaused) "1" else "0")
            }
            db.insertWithOnConflict("device_state", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    fun isDevicePaused(): Boolean {
        readableDatabase.use { db ->
            db.rawQuery("SELECT value FROM device_state WHERE key = 'is_paused'", null).use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getString(0) == "1"
                }
            }
        }
        return false
    }

    // ==========================================
    // Temporary Unblock Grants
    // ==========================================
    fun grantTemporaryUnblock(packageName: String, durationMinutes: Int) {
        val expiresAt = System.currentTimeMillis() + (durationMinutes * 60 * 1000L)
        writableDatabase.use { db ->
            val cv = ContentValues().apply {
                put("package_name", packageName)
                put("expires_at", expiresAt)
            }
            db.insertWithOnConflict("unblock_grants", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    fun hasTemporaryUnblock(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        readableDatabase.use { db ->
            db.rawQuery(
                "SELECT expires_at FROM unblock_grants WHERE package_name = ?",
                arrayOf(packageName)
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    val expiresAt = cursor.getLong(0)
                    return expiresAt > now
                }
            }
        }
        return false
    }

    // ==========================================
    // App Policies
    // ==========================================
    fun saveAppPolicies(policiesJson: JSONArray) {
        writableDatabase.use { db ->
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
    }

    fun upsertAppPolicy(policy: JSONObject) {
        writableDatabase.use { db ->
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
    }

    fun getPolicyForPackage(packageName: String): CachedAppPolicy? {
        readableDatabase.use { db ->
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
        }
        return null
    }

    fun getAllPolicies(): List<CachedAppPolicy> {
        val list = mutableListOf<CachedAppPolicy>()
        readableDatabase.use { db ->
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
        }
        return list
    }

    // ==========================================
    // Web Rules
    // ==========================================
    fun saveWebRules(rulesJson: JSONArray) {
        writableDatabase.use { db ->
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
    }

    fun upsertWebRule(rule: JSONObject) {
        writableDatabase.use { db ->
            val cv = ContentValues().apply {
                put("id", rule.optString("_id", rule.optString("id")))
                put("rule_type", rule.getString("ruleType"))
                put("target", rule.getString("target").lowercase().trim())
                put("action", rule.optString("action", "BLOCK"))
                put("is_enabled", if (rule.optBoolean("isEnabled", true)) 1 else 0)
            }
            db.insertWithOnConflict("web_rules", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    fun deleteWebRule(ruleId: String) {
        writableDatabase.use { db ->
            db.delete("web_rules", "id = ?", arrayOf(ruleId))
        }
    }

    fun getAllActiveWebRules(): List<CachedWebRule> {
        val list = mutableListOf<CachedWebRule>()
        readableDatabase.use { db ->
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
        }
        return list
    }

    // ==========================================
    // Browsing History Queue
    // ==========================================
    fun insertBrowsingHistory(entry: CachedBrowsingHistory): Long {
        writableDatabase.use { db ->
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
    }

    fun getUnsyncedBrowsingHistory(limit: Int = 100): List<CachedBrowsingHistory> {
        val list = mutableListOf<CachedBrowsingHistory>()
        readableDatabase.use { db ->
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
        }
        return list
    }

    fun markBrowsingHistorySynced(ids: List<Long>) {
        if (ids.isEmpty()) return
        writableDatabase.use { db ->
            val inClause = ids.joinToString(",") { it.toString() }
            db.execSQL("UPDATE browsing_history SET is_synced = 1 WHERE id IN ($inClause)")
        }
    }
}

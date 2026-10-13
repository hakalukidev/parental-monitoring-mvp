package com.example.childapp.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import com.example.childapp.activity.ActivityMetadata

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
    private val appContext = context.applicationContext

    companion object {
        private const val DATABASE_NAME = "child_monitoring.db"
        private const val DATABASE_VERSION = 8

        @Volatile
        private var instance: LocalDatabase? = null

        fun getInstance(context: Context): LocalDatabase {
            return instance ?: synchronized(this) {
                instance ?: LocalDatabase(context.applicationContext).also { instance = it }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS activity_queue (kind TEXT NOT NULL, event_id TEXT NOT NULL, owner_child_id TEXT NOT NULL DEFAULT '', event_at INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kind,event_id))")
        db.execSQL("CREATE TABLE IF NOT EXISTS activity_seen (kind TEXT NOT NULL, event_id TEXT NOT NULL, event_at INTEGER NOT NULL, PRIMARY KEY(kind,event_id))")
        db.execSQL("CREATE TABLE IF NOT EXISTS pending_locations (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS app_policies (
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
            CREATE TABLE IF NOT EXISTS web_rules (
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
            CREATE TABLE IF NOT EXISTS browsing_history (
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
            CREATE TABLE IF NOT EXISTS unblock_grants (
                package_name TEXT PRIMARY KEY,
                expires_at INTEGER,
                expires_elapsed INTEGER,
                boot_count INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS device_state (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS geofences (
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
            CREATE TABLE IF NOT EXISTS blocked_events (
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
        onCreate(db) // All CREATE statements are additive and idempotent.
        val columns = mutableSetOf<String>()
        db.rawQuery("PRAGMA table_info(unblock_grants)", null).use { c -> while (c.moveToNext()) columns.add(c.getString(1)) }
        if ("expires_elapsed" !in columns) db.execSQL("ALTER TABLE unblock_grants ADD COLUMN expires_elapsed INTEGER")
        if ("boot_count" !in columns) db.execSQL("ALTER TABLE unblock_grants ADD COLUMN boot_count INTEGER")
        val activityColumns=mutableSetOf<String>()
        db.rawQuery("PRAGMA table_info(activity_queue)",null).use {c->while(c.moveToNext())activityColumns.add(c.getString(1))}
        if("owner_child_id" !in activityColumns)db.execSQL("ALTER TABLE activity_queue ADD COLUMN owner_child_id TEXT NOT NULL DEFAULT ''")
    }
    @Synchronized fun queueLocation(payload: JSONObject) {
        writableDatabase.insert("pending_locations", null, ContentValues().apply { put("payload", payload.toString()) })
        // Bound offline storage; retain the latest 2,000 fixes.
        writableDatabase.execSQL("DELETE FROM pending_locations WHERE id NOT IN (SELECT id FROM pending_locations ORDER BY id DESC LIMIT 2000)")
    }
    @Synchronized fun pendingLocations(): List<Pair<Long, JSONObject>> {
        val result = mutableListOf<Pair<Long, JSONObject>>()
        readableDatabase.rawQuery("SELECT id, payload FROM pending_locations ORDER BY id ASC LIMIT 100", null).use { c -> while (c.moveToNext()) result.add(c.getLong(0) to JSONObject(c.getString(1))) }
        return result
    }
    @Synchronized fun markLocationsSynced(ids: List<Long>) {
        for (id in ids) writableDatabase.delete("pending_locations", "id = ?", arrayOf(id.toString()))
    }
    @Synchronized fun clearAccountData() {
        val db = writableDatabase; db.beginTransaction()
        try {
            for (table in listOf("app_policies", "web_rules", "browsing_history", "unblock_grants", "device_state", "geofences", "blocked_events", "pending_locations", "activity_queue", "activity_seen")) db.delete(table, null, null)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    // ==========================================
    // Device Lockdown State
    // ==========================================
    @Synchronized fun setLocalState(key: String, value: String) {
        writableDatabase.insertWithOnConflict("device_state",null,ContentValues().apply {put("key",key);put("value",value)},SQLiteDatabase.CONFLICT_REPLACE)
    }
    @Synchronized fun localState(key: String): String? = readableDatabase.rawQuery("SELECT value FROM device_state WHERE key = ?",arrayOf(key)).use { if(it.moveToFirst())it.getString(0) else null }
    @Synchronized fun queueActivity(event: JSONObject, expectedChildId: String) {
        if(SessionStore(appContext).childId!=expectedChildId)return
        val kind=event.getString("kind"); val id=ActivityMetadata.hash("$expectedChildId:${event.getString("eventId")}")
        val ownedEvent=JSONObject(event.toString()).put("eventId",id)
        val at=java.time.Instant.parse(event.getString("eventAt")).toEpochMilli()
        val db=writableDatabase;db.beginTransaction()
        try {
            val seen=db.insertWithOnConflict("activity_seen",null,ContentValues().apply {put("kind",kind);put("event_id",id);put("event_at",at)},SQLiteDatabase.CONFLICT_IGNORE)
            if(seen != -1L) {
                db.insertWithOnConflict("activity_queue",null,ContentValues().apply {put("kind",kind);put("event_id",id);put("owner_child_id",expectedChildId);put("event_at",at);put("payload",ownedEvent.toString())},SQLiteDatabase.CONFLICT_IGNORE)
                val removed=db.delete("activity_queue","kind = ? AND event_id NOT IN (SELECT event_id FROM activity_queue WHERE kind = ? ORDER BY event_at DESC LIMIT 2000)",arrayOf(kind,kind))
                if(removed>0) setLocalState("activity_dropped",((localState("activity_dropped")?.toIntOrNull() ?: 0)+removed).toString())
                db.delete("activity_seen","kind = ? AND event_id NOT IN (SELECT event_id FROM activity_seen WHERE kind = ? ORDER BY event_at DESC LIMIT 4000)",arrayOf(kind,kind))
            }
            db.setTransactionSuccessful()
        } finally {db.endTransaction()}
    }
    @Synchronized fun pendingActivity(kind:String): List<JSONObject> = readableDatabase.rawQuery("SELECT payload FROM activity_queue WHERE kind = ? AND owner_child_id = ? ORDER BY event_at ASC LIMIT 100",arrayOf(kind,SessionStore(appContext).childId ?: "NONE")).use { c -> mutableListOf<JSONObject>().apply {while(c.moveToNext())add(JSONObject(c.getString(0)))} }
    @Synchronized fun markActivitySynced(kind:String, ids:List<String>) {for(id in ids)writableDatabase.delete("activity_queue","kind = ? AND event_id = ?",arrayOf(kind,id))}
    @Synchronized fun clearPendingActivity(kind:String) {writableDatabase.delete("activity_queue","kind = ?",arrayOf(kind))}
    @Synchronized fun activityQueueCount(): Int = readableDatabase.rawQuery("SELECT COUNT(*) FROM activity_queue WHERE owner_child_id = ?",arrayOf(SessionStore(appContext).childId ?: "NONE")).use {it.moveToFirst();it.getInt(0)}
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
        val expiresAt = System.currentTimeMillis() + (durationMinutes.coerceIn(1, 120) * 60 * 1000L)
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("package_name", packageName)
            put("expires_at", expiresAt)
            put("expires_elapsed", android.os.SystemClock.elapsedRealtime() + durationMinutes.coerceIn(1, 120) * 60_000L)
            put("boot_count", android.provider.Settings.Global.getInt(appContext.contentResolver, "boot_count", -1))
        }
        db.insertWithOnConflict("unblock_grants", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Synchronized
    fun hasTemporaryUnblock(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        val db = readableDatabase
        db.rawQuery(
            "SELECT expires_at, expires_elapsed, boot_count FROM unblock_grants WHERE package_name = ?",
            arrayOf(packageName)
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val expiresAt = cursor.getLong(0)
                return expiresAt > now && !cursor.isNull(1) && cursor.getLong(1) > android.os.SystemClock.elapsedRealtime() && !cursor.isNull(2) && cursor.getInt(2) == android.provider.Settings.Global.getInt(appContext.contentResolver, "boot_count", -1)
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
        if (entry.isIncognito) return -1L
        val safeUrl = entry.url.replace(Regex("^(https?://)[^/@]*@"), "$1").substringBefore('?').substringBefore('#')
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("url", safeUrl)
            put("domain", entry.domain)
            put("title", entry.title.take(300))
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
        db.execSQL("DELETE FROM browsing_history WHERE id IN ($inClause)")
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

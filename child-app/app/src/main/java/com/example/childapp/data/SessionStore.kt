package com.example.childapp.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/** Persists the child's access token + basic profile between launches. */
class SessionStore(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "child_session",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    var accessToken: String?
        get() = prefs.getString(KEY_ACCESS_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_ACCESS_TOKEN, value).apply()

    var childName: String?
        get() = prefs.getString(KEY_CHILD_NAME, null)
        set(value) = prefs.edit().putString(KEY_CHILD_NAME, value).apply()

    var parentName: String?
        get() = prefs.getString(KEY_PARENT_NAME, null)
        set(value) = prefs.edit().putString(KEY_PARENT_NAME, value).apply()

    var childId: String?
        get() = prefs.getString(KEY_CHILD_ID, null)
        set(value) = prefs.edit().putString(KEY_CHILD_ID, value).apply()

    fun clear() = prefs.edit().clear().apply()

    companion object {
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_CHILD_ID = "child_id"
        private const val KEY_CHILD_NAME = "child_name"
        private const val KEY_PARENT_NAME = "parent_name"
    }
}

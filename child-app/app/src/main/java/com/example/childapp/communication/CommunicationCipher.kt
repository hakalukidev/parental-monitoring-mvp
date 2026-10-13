package com.example.childapp.communication

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The key never leaves Android Keystore; normal APK updates preserve it. No biometric prompt per sync. */
object CommunicationCipher {
    private const val alias="seftly_communication_queue_v1"
    @Synchronized private fun key():SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore").apply {load(null)}
        (store.getKey(alias,null) as? SecretKey)?.let {return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        }.generateKey()
    }
    fun seal(owner:String,raw:String):String {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key());cipher.updateAAD(owner.toByteArray(Charsets.UTF_8))
        return "v1."+Base64.encodeToString(cipher.iv,Base64.NO_WRAP)+"."+Base64.encodeToString(cipher.doFinal(raw.toByteArray(Charsets.UTF_8)),Base64.NO_WRAP)
    }
    fun open(owner:String,sealed:String):String {
        val parts=sealed.split('.');require(parts.size==3&&parts[0]=="v1")
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,Base64.decode(parts[1],Base64.NO_WRAP)));cipher.updateAAD(owner.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(Base64.decode(parts[2],Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }
}

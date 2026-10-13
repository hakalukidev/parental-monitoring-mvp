package com.example.childapp.activity

import java.security.MessageDigest

object ActivityMetadata {
    fun hash(value:String):String = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    fun sensitivePackage(name:String):Boolean = Regex("(?:^com\\.example\\.(?:childapp|parent_app)(?:\\.debug|\\.qa)?$|^android$|^com\\.android\\.|bank|wallet|authenticator|password|bitwarden|1password|lastpass)",RegexOption.IGNORE_CASE).containsMatchIn(name)
    fun maskedIdentifier(value:String):String? = value.filter(Char::isDigit).takeLast(4).takeIf {it.isNotEmpty()}?.let {"****$it"}
    fun callDirection(type:Int):String? = when(type) {1->"INCOMING";2->"OUTGOING";3->"MISSED";5->"REJECTED";6->"BLOCKED";else->null}
    fun smsDirection(type:Int):String? = when(type) {1->"INCOMING";2->"OUTGOING";else->null}
}

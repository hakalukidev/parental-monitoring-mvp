package com.example.childapp.communication

data class SafeMessageBody(val text:String?,val status:String)
object CommunicationPrivacy {
    private val secrets=Regex("(?:\\botp\\b|one[ -]?time|verification|authentication|security code|\\bpassword\\b|passcode|\\bpin\\b|\\b2fa\\b|log[ -]?in|sign[ -]?in|bank|wallet|reset|ভেরিফিকেশন|যাচাই|পাসওয়ার্ড|ওটিপি|গোপন|পিন|[?&](?:token|secret|password|otp|code)=|\\bBearer\\s|\\beyJ[a-zA-Z\\d_-]{15})",RegexOption.IGNORE_CASE)
    fun body(raw:String?,address:String,authorized:Boolean):SafeMessageBody {
        if(!authorized)return SafeMessageBody(null,"NOT_AUTHORIZED")
        if(raw==null)return SafeMessageBody(null,"NOT_REPORTED")
        if(raw.isEmpty())return SafeMessageBody(null,"EMPTY")
        if(secrets.containsMatchIn(raw)||Regex("bank|wallet|auth|otp|verify",RegexOption.IGNORE_CASE).containsMatchIn(address))return SafeMessageBody(null,"WITHHELD_SECURITY")
        if(raw.length>32000)return SafeMessageBody(null,"TOO_LARGE")
        return SafeMessageBody(raw,"AVAILABLE")
    }
    /** SMS provider bodies are already multipart-assembled by Android; MMS text parts preserve provider order. */
    fun assembleTextParts(parts:List<String>):String=parts.joinToString("\n")
    fun deliveryStatus(status:Int?):String=when(status){-1->"NONE";0->"COMPLETE";32->"PENDING";64->"FAILED";else->"UNKNOWN"}
}

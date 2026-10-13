package com.example.childapp.consent

/** Platform policy only. MediaProjection always needs its own new system grant. */
object MediaActivationPolicy {
    fun canUseExistingGrant(androidApi:Int,kind:String,permissionsGranted:Boolean,appVisible:Boolean):Boolean =
        kind in setOf("camera","audio")&&permissionsGranted&&(appVisible||androidApi in 26..29)
}

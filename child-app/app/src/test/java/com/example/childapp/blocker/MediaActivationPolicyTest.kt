package com.example.childapp.blocker
import com.example.childapp.consent.MediaActivationPolicy
import org.junit.Assert.*
import org.junit.Test
class MediaActivationPolicyTest {
    @Test fun validPermissionsNeedNoExtraAppApprovalWhileVisible() {
        for(api in listOf(26,29,30,34,36))for(kind in listOf("camera","audio"))assertTrue(MediaActivationPolicy.canUseExistingGrant(api,kind,true,true))
    }
    @Test fun newAndroidNeedsPermittedForegroundAndScreenAlwaysNeedsFreshSystemGrant() {
        for(api in listOf(30,34,36))assertFalse(MediaActivationPolicy.canUseExistingGrant(api,"audio",true,false))
        for(api in listOf(26,30,36))assertFalse(MediaActivationPolicy.canUseExistingGrant(api,"screen",true,true))
        assertFalse(MediaActivationPolicy.canUseExistingGrant(36,"camera",false,true))
        assertTrue(MediaActivationPolicy.canUseExistingGrant(29,"camera",true,false))
    }
}

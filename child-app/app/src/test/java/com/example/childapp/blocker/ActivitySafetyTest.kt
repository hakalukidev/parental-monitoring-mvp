package com.example.childapp.blocker

import com.example.childapp.activity.ActivityMetadata
import com.example.childapp.safety.SafetyScores
import com.example.childapp.safety.SafetyDecisions
import org.junit.Assert.*
import org.junit.Test

class ActivitySafetyTest {
    @Test fun identifiersAreMinimizedAndProtectedNotificationPackagesAreExcluded() {
        assertEquals("****1234",ActivityMetadata.maskedIdentifier("+880 17000 1234"))
        assertNull(ActivityMetadata.maskedIdentifier("Anonymous"))
        assertEquals(64,ActivityMetadata.hash("synthetic identifier only").length)
        for(pkg in listOf("com.example.childapp","com.android.systemui","com.fixture.bank","com.google.android.apps.authenticator2","com.bitwarden.mobile"))assertTrue(ActivityMetadata.sensitivePackage(pkg))
        assertFalse(ActivityMetadata.sensitivePackage("com.fixture.chat"))
    }
    @Test fun supportedCallSmsMetadataNeverClassifiesDraftsAsSent() {
        assertEquals("MISSED",ActivityMetadata.callDirection(3));assertEquals("OUTGOING",ActivityMetadata.callDirection(2))
        assertEquals("INCOMING",ActivityMetadata.smsDirection(1));assertEquals("OUTGOING",ActivityMetadata.smsDirection(2));assertNull(ActivityMetadata.smsDirection(3))
    }
    /** Deterministic test-only score fixture; no production model or accuracy claim. */
    private fun explicitlyTestOnlyModel(input:Float):SafetyScores=SafetyScores(input,0f)
    @Test fun testOnlyScoresRespectThresholdUncertaintyAndVideoCorroboration() {
        assertNull(SafetyDecisions.image(explicitlyTestOnlyModel(.1f),.8f,.5f))
        assertEquals("UNCERTAIN",SafetyDecisions.image(explicitlyTestOnlyModel(.6f),.8f,.5f)?.category)
        assertEquals("POTENTIAL_ADULT",SafetyDecisions.image(explicitlyTestOnlyModel(.9f),.8f,.5f)?.category)
        assertEquals("UNCERTAIN",SafetyDecisions.video(listOf(explicitlyTestOnlyModel(.9f),explicitlyTestOnlyModel(.1f)),.8f,.5f)?.category)
        assertEquals("POTENTIAL_ADULT",SafetyDecisions.video(listOf(explicitlyTestOnlyModel(.9f),explicitlyTestOnlyModel(.85f)),.8f,.5f)?.category)
    }
    @Test fun samplingIsBoundedAndDoesNotReadPastTheVideo() {
        val times=SafetyDecisions.sampleTimes(1_000_000)
        assertEquals(8,times.size);assertEquals(0L,times.first());assertTrue(times.last()<1_000_000)
        assertTrue(times.zipWithNext().all {it.first<it.second})
        assertThrows(IllegalArgumentException::class.java){SafetyScores(Float.NaN,0f)}
        assertThrows(IllegalArgumentException::class.java){SafetyDecisions.sampleTimes(0)}
    }
}

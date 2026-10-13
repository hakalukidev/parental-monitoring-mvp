package com.example.childapp.blocker
import com.example.childapp.communication.CommunicationPrivacy
import org.junit.Assert.*
import org.junit.Test

class CommunicationPrivacyTest {
    @Test fun providerAssembledMultipartBodyIsPreservedButSecuritySecretsAreWithheld() {
        val body="Synthetic school message. ".repeat(80)+"শেষ অংশ"
        assertEquals(body,CommunicationPrivacy.body(body,"+15550101234",true).text)
        for(secret in listOf("OTP 123456","WiFi password sunshine","Verification code 000000","ওটিপি ১২৩৪৫৬","https://example.test/?token=private"))assertEquals("WITHHELD_SECURITY",CommunicationPrivacy.body(secret,"QA",true).status)
        assertEquals("NOT_AUTHORIZED",CommunicationPrivacy.body(body,"QA",false).status)
        assertEquals("TOO_LARGE",CommunicationPrivacy.body("x".repeat(32001),"QA",true).status)
        assertEquals("NOT_REPORTED",CommunicationPrivacy.body(null,"QA",true).status)
        assertEquals("EMPTY",CommunicationPrivacy.body("","QA",true).status)
    }
    @Test fun mmsTextPartsKeepOrderAndDeliveryUnknownIsNeverFabricated() {
        assertEquals("Part one\nPart two",CommunicationPrivacy.assembleTextParts(listOf("Part one","Part two")))
        assertEquals("NONE",CommunicationPrivacy.deliveryStatus(-1));assertEquals("COMPLETE",CommunicationPrivacy.deliveryStatus(0))
        assertEquals("PENDING",CommunicationPrivacy.deliveryStatus(32));assertEquals("FAILED",CommunicationPrivacy.deliveryStatus(64))
        assertEquals("UNKNOWN",CommunicationPrivacy.deliveryStatus(null))
    }
}

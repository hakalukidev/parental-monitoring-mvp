package com.example.childapp.blocker

import org.junit.Assert.*
import org.junit.Test
import com.example.childapp.data.CachedWebRule
import java.time.Instant
import java.time.ZoneId

class MonitoringLogicTest {
    @Test fun overnightRestrictionBelongsToItsStartingDay() {
        assertTrue(PolicySchedule.active(setOf(1), 22 * 60, 7 * 60, 1, 23 * 60))
        assertTrue(PolicySchedule.active(setOf(1), 22 * 60, 7 * 60, 2, 6 * 60))
        assertFalse(PolicySchedule.active(setOf(1), 22 * 60, 7 * 60, 1, 6 * 60))
        assertFalse(PolicySchedule.active(setOf(1), 22 * 60, 7 * 60, 2, 7 * 60))
    }
    @Test fun schedulesHandleEmptyDaysEqualTimesAndSundayWrap() {
        assertFalse(PolicySchedule.active(emptySet(), 0, 0, 1, 1))
        assertTrue(PolicySchedule.active(setOf(1), 300, 300, 1, 0))
        assertTrue(PolicySchedule.active(setOf(6), 1320, 420, 0, 100))
        assertFalse(PolicySchedule.active(setOf(1), 60, 120, 1, 120))
    }
    @Test fun activeIntervalIsSplitAcrossHoursAndUnmatchedPauseDoesNotCloseAnotherApp() {
        val t = Instant.parse("2026-10-12T10:50:00Z").toEpochMilli()
        val totals = UsageTimeline.aggregate(listOf(UsageEventPoint(t, 1, "app.a"), UsageEventPoint(t + 5*60_000, 2, "app.b"), UsageEventPoint(t + 20*60_000, 2, "app.a")), t, t+30*60_000, ZoneId.of("UTC"))
        assertEquals(1200L, totals.perPackageSeconds["app.a"])
        assertEquals(600L, totals.hourlySeconds[10]); assertEquals(600L, totals.hourlySeconds[11])
        assertNull(totals.screenOffSeconds); assertEquals(1, totals.launches["app.a"])
    }
    @Test fun foregroundAcrossMidnightIsClippedAndStillOpenIntervalIncluded() {
        val midnight = Instant.parse("2026-10-12T00:00:00Z").toEpochMilli()
        val totals = UsageTimeline.aggregate(listOf(UsageEventPoint(midnight - 60_000, 1, "app.a")), midnight, midnight+120_000, ZoneId.of("UTC"))
        assertEquals(120L, totals.perPackageSeconds["app.a"]); assertEquals(0, totals.launches["app.a"] ?: 0)
    }
    @Test fun screenOffIsIndependentOfForegroundAndShutdownStopsUsage() {
        val start = Instant.parse("2026-10-12T00:00:00Z").toEpochMilli()
        val totals = UsageTimeline.aggregate(listOf(UsageEventPoint(start-1, 15), UsageEventPoint(start, 1, "app.a"), UsageEventPoint(start+10_000, 16), UsageEventPoint(start+40_000, 15), UsageEventPoint(start+41_000, 1, "app.b"), UsageEventPoint(start+50_000, 26)), start, start+60_000, ZoneId.of("UTC"))
        assertEquals(30L, totals.screenOffSeconds); assertEquals(10L, totals.perPackageSeconds["app.a"]); assertEquals(9L, totals.perPackageSeconds["app.b"])
    }
    @Test fun duplicateResumeDoesNotDoubleCountAndTimezoneBucketsUseChildZone() {
        val start = Instant.parse("2026-10-11T18:00:00Z").toEpochMilli()
        val totals = UsageTimeline.aggregate(listOf(UsageEventPoint(start, 1, "app.a"), UsageEventPoint(start+10_000, 1, "app.a")), start, start+60_000, ZoneId.of("Asia/Dhaka"))
        assertEquals(60L, totals.perPackageSeconds["app.a"]); assertEquals(1, totals.launches["app.a"]); assertEquals(60L, totals.hourlySeconds[0])
    }
    @Test fun webRulesRespectHostBoundariesAllowOverridesAndDisabledRules() {
        val block = CachedWebRule("block", "DOMAIN", "example.com", "BLOCK", true)
        assertTrue(WebFilterEvaluator.evaluateRules("https://sub.example.com/path", rules = listOf(block)).isBlocked)
        assertFalse(WebFilterEvaluator.evaluateRules("https://example.com.evil.test", rules = listOf(block)).isBlocked)
        assertFalse(WebFilterEvaluator.evaluateRules("https://notexample.com", rules = listOf(block)).isBlocked)
        assertFalse(WebFilterEvaluator.evaluateRules("https://example.com", rules = listOf(block.copy(isEnabled = false))).isBlocked)
        val allow = block.copy(id = "allow", target = "study.example.com", action = "ALLOW")
        assertFalse(WebFilterEvaluator.evaluateRules("https://study.example.com", rules = listOf(block, allow)).isBlocked)
    }
    @Test fun encodedKeywordsAndMalformedUrlsDoNotCrash() {
        val keyword = CachedWebRule("keyword", "KEYWORD", "bad word", "BLOCK", true)
        assertTrue(WebFilterEvaluator.evaluateRules("https://search.test/?q=bad%20word", rules = listOf(keyword)).isBlocked)
        assertFalse(WebFilterEvaluator.evaluateRules("https://%invalid", rules = emptyList()).isBlocked)
    }

}

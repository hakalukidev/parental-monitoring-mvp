package com.example.childapp.blocker

import java.time.Instant
import java.time.ZoneId

data class UsageEventPoint(val timestamp: Long, val type: Int, val packageName: String? = null)
data class UsageTotals(val perPackageSeconds: Map<String, Long>, val lastUsed: Map<String, Long>, val launches: Map<String, Int>, val hourlySeconds: List<Long>, val screenOffSeconds: Long?)

/** Event intervals clipped to the child's local day. Screen-off is measured independently. */
object UsageTimeline {
    const val RESUMED = 1
    const val PAUSED = 2
    const val SCREEN_ON = 15
    const val SCREEN_OFF = 16
    const val SHUTDOWN = 26
    fun aggregate(events: List<UsageEventPoint>, start: Long, end: Long, zone: ZoneId): UsageTotals {
        require(end >= start)
        val usage = mutableMapOf<String, Long>(); val last = mutableMapOf<String, Long>(); val launches = mutableMapOf<String, Int>()
        val hours = LongArray(24)
        var current: String? = null; var since = start
        var screenOn: Boolean? = null; var screenSince = start; var offMs = 0L
        var stateAtStart: Boolean? = null
        fun addUsage(until: Long) {
            val pkg = current ?: return
            var cursor = maxOf(start, since); val stop = minOf(end, until)
            if (stop <= cursor) return
            usage[pkg] = (usage[pkg] ?: 0L) + stop - cursor
            last[pkg] = stop
            while (cursor < stop) {
                val local = Instant.ofEpochMilli(cursor).atZone(zone)
                val next = local.withMinute(0).withSecond(0).withNano(0).plusHours(1).toInstant().toEpochMilli()
                val boundary = minOf(stop, maxOf(cursor + 1, next))
                hours[local.hour] += boundary - cursor; cursor = boundary
            }
        }
        for (event in events.sortedBy { it.timestamp }.filter { it.timestamp <= end }) {
            if (event.timestamp <= start && event.type == SCREEN_ON) stateAtStart = true
            if (event.timestamp <= start && event.type == SCREEN_OFF) stateAtStart = false
            when (event.type) {
                RESUMED -> if (event.packageName != null && event.packageName != current) {
                    addUsage(event.timestamp); current = event.packageName; since = event.timestamp
                    if (event.timestamp >= start) launches[event.packageName] = (launches[event.packageName] ?: 0) + 1
                }
                PAUSED -> if (current == event.packageName) { addUsage(event.timestamp); current = null }
                SCREEN_ON, SCREEN_OFF -> {
                    if (screenOn == false) offMs += (minOf(end, event.timestamp) - maxOf(start, screenSince)).coerceAtLeast(0)
                    screenOn = event.type == SCREEN_ON; screenSince = event.timestamp
                    if (!screenOn) { addUsage(event.timestamp); current = null }
                }
                SHUTDOWN -> {
                    addUsage(event.timestamp); current = null
                    if (screenOn == false) offMs += (minOf(end, event.timestamp) - maxOf(start, screenSince)).coerceAtLeast(0)
                    screenOn = null
                }
            }
        }
        addUsage(end)
        if (screenOn == false) offMs += (end - maxOf(start, screenSince)).coerceAtLeast(0)
        return UsageTotals(usage.mapValues { it.value / 1000 }, last, launches, hours.map { it / 1000 }, if (stateAtStart == null) null else offMs / 1000)
    }
}

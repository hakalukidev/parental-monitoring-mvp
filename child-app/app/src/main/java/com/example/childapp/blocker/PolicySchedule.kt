package com.example.childapp.blocker

/** Days refer to the day a restriction starts; end is exclusive. Equal times mean a full selected day. */
object PolicySchedule {
    fun active(days: Set<Int>, startMinute: Int, endMinute: Int, currentDay: Int, currentMinute: Int): Boolean {
        require(currentDay in 0..6 && currentMinute in 0..1439 && startMinute in 0..1439 && endMinute in 0..1439)
        if (startMinute == endMinute) return currentDay in days
        if (startMinute < endMinute) return currentDay in days && currentMinute >= startMinute && currentMinute < endMinute
        return (currentDay in days && currentMinute >= startMinute) || ((currentDay + 6) % 7 in days && currentMinute < endMinute)
    }
}

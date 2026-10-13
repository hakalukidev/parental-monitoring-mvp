package com.example.childapp.safety

data class SafetyScores(val adult:Float,val violence:Float) {
    init {require(adult.isFinite()&&violence.isFinite()&&adult in 0f..1f&&violence in 0f..1f)}
}
data class SafetyDecision(val category:String,val confidence:Float)
object SafetyDecisions {
    fun image(scores:SafetyScores,threshold:Float,uncertain:Float):SafetyDecision? {
        require(threshold in .5f..1f&&uncertain in 0f..threshold)
        val peak=maxOf(scores.adult,scores.violence)
        return when {peak>=threshold->SafetyDecision(if(scores.adult>=scores.violence)"POTENTIAL_ADULT" else "POTENTIAL_VIOLENCE",peak);peak>=uncertain->SafetyDecision("UNCERTAIN",peak);else->null}
    }
    fun video(frames:List<SafetyScores>,threshold:Float,uncertain:Float):SafetyDecision? {
        require(frames.isNotEmpty()&&frames.size<=12)
        val peak=frames.maxBy {maxOf(it.adult,it.violence)}
        val decision=image(peak,threshold,uncertain) ?: return null
        val corroborated=frames.count {if(decision.category=="POTENTIAL_ADULT")it.adult>=threshold else if(decision.category=="POTENTIAL_VIOLENCE")it.violence>=threshold else false}>=2
        return if(decision.category!="UNCERTAIN"&&!corroborated)SafetyDecision("UNCERTAIN",decision.confidence) else decision
    }
    fun sampleTimes(durationUs:Long,count:Int=8):List<Long> {require(durationUs>0&&count in 2..12);return (0 until count).map {durationUs*it/(count-1)}.map {it.coerceAtMost(durationUs-1)}}
}

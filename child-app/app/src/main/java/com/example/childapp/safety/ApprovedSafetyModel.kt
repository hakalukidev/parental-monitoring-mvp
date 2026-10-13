package com.example.childapp.safety

import android.content.Context
import android.graphics.Bitmap
import org.json.JSONObject
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import com.example.childapp.activity.ActivityMetadata

/** No model is bundled. Only a licensed, evaluated model bundled in the signed APK can activate inference. */
class ApprovedSafetyModel private constructor(context:Context, val manifest:JSONObject):AutoCloseable {
    val version=manifest.getString("version")
    val threshold=manifest.getDouble("threshold").toFloat()
    val uncertain=manifest.getDouble("uncertainThreshold").toFloat()
    val labels=manifest.getJSONArray("labels")
    private val interpreter:Interpreter
    val width:Int
    val height:Int
    init {
        val file=manifest.getString("asset")
        require(file.matches(Regex("[a-zA-Z0-9._-]+\\.tflite")))
        val bytes=context.assets.open("safety/$file").use {stream ->
            val output=java.io.ByteArrayOutputStream();val buffer=ByteArray(16384)
            while(true) {val count=stream.read(buffer);if(count<0)break;require(output.size()+count<=32*1024*1024);output.write(buffer,0,count)}
            output.toByteArray()
        }
        require(bytes.size in 1..32*1024*1024)
        val actual=java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
        require(actual==manifest.getString("sha256"))
        interpreter=Interpreter(ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply {put(bytes);rewind()},Interpreter.Options().setNumThreads(2))
        try {
            val input=interpreter.getInputTensor(0);val output=interpreter.getOutputTensor(0)
            require(input.dataType()==DataType.FLOAT32&&output.dataType()==DataType.FLOAT32)
            val shape=input.shape();require(shape.size==4&&shape[0]==1&&shape[3]==3&&shape[1] in 32..384&&shape[2] in 32..384)
            height=shape[1];width=shape[2]
            require(output.shape().contentEquals(intArrayOf(1,labels.length())))
        } catch(error:Exception) {interpreter.close();throw error}
    }
    fun infer(bitmap:Bitmap):SafetyScores {
        val resized=Bitmap.createScaledBitmap(bitmap,width,height,true)
        try {
        val input=ByteBuffer.allocateDirect(width*height*3*4).order(ByteOrder.nativeOrder())
        val pixels=IntArray(width*height);resized.getPixels(pixels,0,width,0,0,width,height)
        for(pixel in pixels) {input.putFloat(((pixel shr 16) and 255)/255f);input.putFloat(((pixel shr 8) and 255)/255f);input.putFloat((pixel and 255)/255f)}
        input.rewind();val output=arrayOf(FloatArray(labels.length()));interpreter.run(input,output)
        require(output[0].all {it.isFinite()&&it in 0f..1f})
        fun score(label:String):Float {val i=(0 until labels.length()).firstOrNull {labels.getString(it)==label};return if(i==null)0f else output[0][i]}
        return SafetyScores(score("POTENTIAL_ADULT"),score("POTENTIAL_VIOLENCE"))
        } finally {if(resized!==bitmap)resized.recycle()}
    }
    override fun close(){interpreter.close()}
    companion object {
        fun manifest(context:Context):JSONObject? = runCatching {
            val data=JSONObject(context.assets.open("safety/model.json").bufferedReader().use {it.readText()})
            require(data.getBoolean("validated")&&!data.optBoolean("testOnly"))
            require(data.getString("version").matches(Regex("[a-zA-Z0-9._-]{1,100}")))
            require(data.getString("license").isNotBlank()&&data.getString("modelCard").startsWith("https://"))
            val validation=data.getJSONObject("evaluation")
            require(validation.getString("datasetProvenance").isNotBlank())
            for(key in listOf("precision","recall","falsePositiveRate","falseNegativeRate"))require(validation.getDouble(key).isFinite()&&validation.getDouble(key) in 0.0..1.0)
            require(validation.getDouble("latencyMs")>0&&validation.getLong("peakMemoryBytes")>0&&validation.getDouble("batteryMeasurementWh")>=0)
            require(data.getDouble("threshold") in .5..1.0&&data.getDouble("uncertainThreshold") in 0.0..data.getDouble("threshold"))
            val labels=data.getJSONArray("labels");require(labels.length() in 2..3)
            require((0 until labels.length()).all {labels.getString(it) in setOf("SAFE","POTENTIAL_ADULT","POTENTIAL_VIOLENCE")})
            data
        }.getOrNull()
        fun open(context:Context):ApprovedSafetyModel?=manifest(context)?.let {runCatching {ApprovedSafetyModel(context,it)}.getOrNull()}
    }
}

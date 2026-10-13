package com.example.parent_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"seftly/app_info").setMethodCallHandler { call,result ->
            if(call.method!="getAppInfo")result.notImplemented()
            else {
                val info=packageManager.getPackageInfo(packageName,0)
                result.success(mapOf("version" to info.versionName,"build" to (if(Build.VERSION.SDK_INT>=28)info.longVersionCode else info.versionCode.toLong())))
            }
        }
    }
}

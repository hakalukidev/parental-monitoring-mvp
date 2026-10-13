package com.example.childapp.audio

import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.atomic.AtomicBoolean

class MediaCaptureState {
    val status = MutableStateFlow("OFF")
    val running = AtomicBoolean(false)
    @Volatile var sessionId: String? = null
    @Volatile var audioEnabled = false
}

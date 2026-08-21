plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.childapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.childapp"
        minSdk = 26 // MediaProjection + foreground service type requirements
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        // Point this at your VPS-hosted backend (use wss:// once TLS is set up).
        buildConfigField("String", "API_BASE_URL", "\"https://api.hakaluki.dev\"")
        buildConfigField("String", "SOCKET_URL", "\"https://api.hakaluki.dev\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Real-time signaling
    implementation("io.socket:socket.io-client:2.1.1") {
        exclude(group = "org.json", module = "json")
    }

    // WebRTC (GetStream's maintained build of the Google WebRTC AAR)
    implementation("io.getstream:stream-webrtc-android:1.1.1")

    // Networking for REST calls
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.json:json:20240303")

    // Encrypted local token storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}

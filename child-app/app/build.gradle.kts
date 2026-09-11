plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.childapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.childapp"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        // Backend
        buildConfigField(
            "String",
            "API_BASE_URL",
            "\"https://163.227.239.88\""
        )

        buildConfigField(
            "String",
            "SOCKET_URL",
            "\"https://163.227.239.88\""
        )
    }

    // =========================================================
    // RELEASE SIGNING
    // =========================================================
    signingConfigs {
        create("release") {
            storeFile = file("../childapp-release-key.jks")
            storePassword = "123457"
            keyAlias = "childapp"
            keyPassword = "123457"
        }
    }

    // =========================================================
    // BUILD TYPES
    // =========================================================
    buildTypes {
        release {
            isMinifyEnabled = false

            // Sign release APK
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // =========================================================
    // BUILD FEATURES
    // =========================================================
    buildFeatures {
        compose = true
        buildConfig = true
    }

    // =========================================================
    // COMPOSE
    // =========================================================
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    // =========================================================
    // JAVA
    // =========================================================
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {

    // =========================================================
    // ANDROIDX
    // =========================================================
    implementation("androidx.core:core-ktx:1.13.1")

    implementation(
        "androidx.lifecycle:lifecycle-runtime-ktx:2.8.4"
    )

    implementation(
        "androidx.activity:activity-compose:1.9.1"
    )

    // =========================================================
    // JETPACK COMPOSE
    // =========================================================
    implementation(
        platform("androidx.compose:compose-bom:2024.06.00")
    )

    implementation("androidx.compose.ui:ui")

    implementation(
        "androidx.compose.ui:ui-graphics"
    )

    implementation(
        "androidx.compose.material3:material3"
    )

    implementation(
        "androidx.compose.material:material-icons-extended:1.6.8"
    )

    // =========================================================
    // VIEWMODEL
    // =========================================================
    implementation(
        "androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4"
    )

    // =========================================================
    // COROUTINES
    // =========================================================
    implementation(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1"
    )

    // =========================================================
    // SOCKET.IO
    // =========================================================
    implementation("io.socket:socket.io-client:2.1.1") {
        exclude(
            group = "org.json",
            module = "json"
        )
    }

    // =========================================================
    // WEBRTC
    // =========================================================
    implementation(
        "io.github.webrtc-sdk:android:125.6422.07"
    )

    // =========================================================
    // NETWORKING
    // =========================================================
    implementation(
        "com.squareup.okhttp3:okhttp:4.12.0"
    )

    implementation(
        "org.json:json:20240303"
    )

    // =========================================================
    // LOCATION (Fused Location Provider)
    // =========================================================
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // =========================================================
    // ENCRYPTED LOCAL STORAGE
    // =========================================================
    implementation(
        "androidx.security:security-crypto:1.1.0-alpha06"
    )
}
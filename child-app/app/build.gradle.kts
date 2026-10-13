import java.net.URI
import java.util.Properties

val releaseSecrets = Properties().apply {
    val secretsFile = rootProject.file("key.properties")
    if (secretsFile.exists()) secretsFile.inputStream().use { load(it) }
}
fun signingValue(name: String): String? = System.getenv("SEFTLY_" + name.replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase())
    ?: releaseSecrets.getProperty(name)
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all { !signingValue(it).isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) } && !hasReleaseSigning) {
    throw GradleException("Release signing requires an ignored key.properties file or SEFTLY_STORE_FILE / STORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD environment variables.")
}

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
        versionCode = 4
        versionName = "1.3.0"
        buildConfigField("boolean", "QA_SAFE_FIXTURES", "false")

        // Backend
        buildConfigField(
            "String",
            "API_BASE_URL",
            "\"https://api.hakaluki.dev\""
        )

        buildConfigField(
            "String",
            "SOCKET_URL",
            "\"https://api.hakaluki.dev\""
        )
    }

    // =========================================================
    // RELEASE SIGNING
    // =========================================================
    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(signingValue("storeFile")!!)
            storePassword = signingValue("storePassword")
            keyAlias = signingValue("keyAlias")
            keyPassword = signingValue("keyPassword")
        }
    }

    buildTypes {
        debug {
            val isolatedQa = providers.gradleProperty("seftlyQa").orNull == "true"
            applicationIdSuffix = if (isolatedQa) ".qa" else ".debug"
            buildConfigField("boolean", "QA_SAFE_FIXTURES", isolatedQa.toString())
            val developmentApi = providers.gradleProperty("developmentApiUrl").orNull
            if (developmentApi != null) {
                val host = URI(developmentApi).host
                if (host !in listOf("10.0.2.2", "127.0.0.1", "localhost")) throw GradleException("Debug cleartext API override is restricted to loopback hosts")
                buildConfigField("String", "API_BASE_URL", "\"$developmentApi\"")
                buildConfigField("String", "SOCKET_URL", "\"$developmentApi\"")
            }
        }
        release {
            isMinifyEnabled = false
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
    }

    lint {
        checkReleaseBuilds = true
        abortOnError = true
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
    implementation("androidx.fragment:fragment-ktx:1.8.2")
    testImplementation("junit:junit:4.13.2")

    // =========================================================
    // ANDROIDX
    // =========================================================
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("org.tensorflow:tensorflow-lite:2.17.0")

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

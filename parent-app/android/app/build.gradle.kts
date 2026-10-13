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
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.parent_app"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.parent_app"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(signingValue("storeFile")!!)
            storePassword = signingValue("storePassword")
            keyAlias = signingValue("keyAlias")
            keyPassword = signingValue("keyPassword")
        }
    }

    buildTypes {
        debug { applicationIdSuffix = if (providers.gradleProperty("seftlyQa").orNull == "true") ".qa" else ".debug" }
        release {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

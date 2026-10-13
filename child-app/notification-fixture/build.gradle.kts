plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "dev.seftly.notificationfixture"
    compileSdk = 34
    defaultConfig {
        applicationId = "dev.seftly.notificationfixture"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "test-only"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

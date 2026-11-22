plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "eu.astonserver.astontv.mobile"
    compileSdk = 35
    defaultConfig {
        applicationId = "eu.astonserver.astontv.mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = 71
        versionName = "7.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

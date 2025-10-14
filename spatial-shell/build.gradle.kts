plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.meta.spatial.plugin") version "0.8.0"
}

android {
    namespace = "com.winston.anki.spatial"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.winston.anki.spatial"
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    packaging {
        jniLibs { useLegacyPackaging = false }
    }
}

dependencies {
    implementation(project(":AnkiDroid")) // troque para :app se precisar
    implementation("com.meta.spatial:meta-spatial-sdk:0.8.0")
    implementation("com.meta.spatial:meta-spatial-sdk-toolkit:0.8.0")
    implementation("com.meta.spatial:meta-spatial-sdk-vr:0.8.0")
    implementation("com.meta.spatial:meta-spatial-sdk-physics:0.8.0")
}

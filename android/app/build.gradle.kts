import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live in android/key.properties (git-ignored;
// see android/key.properties.example). Loaded here so that no secret is ever
// written into this file.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.rhengtl.textsnip"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.rhengtl.textsnip"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Deliberately no fallback to the debug key: a debug-signed APK
            // that slipped out as a release could never be updated in place.
            // Debug builds (`flutter run`) are unaffected.
            signingConfig = signingConfigs.findByName("release")
                ?: throw GradleException(
                    "Release signing is not configured: create android/key.properties " +
                    "from android/key.properties.example (and the keystore it points to)."
                )
        }
    }

}

dependencies {
    // NotificationCompat: lets the capture-session notification support the
    // declared minSdk (24) without touching API 26+ channel classes directly.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}

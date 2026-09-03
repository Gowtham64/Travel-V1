plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase — processes google-services.json for Firebase Analytics (Android only).
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.travel_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 18 needs Java 8+ desugared APIs.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.gowtham64.travelapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // androidx.car.app (Android Auto) requires minSdk 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // Android Auto — Car App Library (CarAppService + NavigationTemplate).
    implementation("androidx.car.app:app:1.4.0")
    // Required by flutter_local_notifications (core library desugaring).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase Analytics (Android). The BoM keeps versions aligned. Analytics
    // auto-collects sessions, first_open, app_open, screen_view, geography and
    // device data once the app runs — no Dart/plugin changes, iOS untouched.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-analytics")
}

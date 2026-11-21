import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val releaseKey = if (signingFile.exists()) Properties().apply {
    signingFile.inputStream().use { load(it) }
} else null

android {
    namespace = "com.example.sableen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.sableen"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        releaseKey?.let { properties ->
            create("release") {
                fun value(key: String) = requireNotNull(properties.getProperty(key)?.takeIf { it.isNotBlank() }) {
                    "Missing $key in android/key.properties"
                }
                storeFile = rootProject.file(value("storeFile"))
                storePassword = value("storePassword")
                keyAlias = value("keyAlias")
                keyPassword = value("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKey == null) "debug" else "release")
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

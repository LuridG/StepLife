plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.steplife.steplife"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.steplife.steplife"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // Debug signing configuration
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // 自动配置 ABI 分包 (arm64-v8a, armeabi-v7a, x86_64 及 Universal 通用包)
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }

    // 自动重命名输出 APK 为规范名称: StepLife-v1.3.0-arm64-v8a.apk / StepLife-v1.3.0-universal.apk
    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            val abiFilter = output.getFilter(com.android.build.OutputFile.ABI)
            val abi = if (abiFilter.isNullOrEmpty()) "universal" else abiFilter
            output.outputFileName = "StepLife-v${variant.versionName}-${abi}.apk"
        }
    }
}

flutter {
    source = "../.."
}

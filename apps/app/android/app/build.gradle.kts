import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "dev.komganative.komga_native"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.yomu.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")?.trim()
                    ?: error("key.properties missing required property: storeFile")
                val resolvedStoreFile = rootProject.file(storeFilePath)
                check(resolvedStoreFile.exists()) {
                    "Release keystore not found: ${resolvedStoreFile.absolutePath}"
                }
                storeFile = resolvedStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("key.properties missing required property: storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("key.properties missing required property: keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("key.properties missing required property: keyPassword")
                // 显式启用 v1 + v2 + v3 全套签名：AGP 8/9 在 minSdk >= 24 下默认关闭 v1 (JAR)，
                // 部分国产 ROM 与 Android 墨水屏安装器会读取 META-INF 证书，缺失 v1 会报"缺乏开发者证书"。
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // 存在 apps/app/android/key.properties 时使用正式签名；
            // 本地开发与日常验证构建未配置时回退 debug 签名，保证 `dart run tool/ci.dart install` 正常可用。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // ADR 0010: Android 原生 CB7 (7z/LZMA2) 与 CBR (RAR4) 解码依赖（零 NDK ABI 体积膨胀）。
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.tukaani:xz:1.10")
    implementation("com.github.junrar:junrar:7.5.5")
}

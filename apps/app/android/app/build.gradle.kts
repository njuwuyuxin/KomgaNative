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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.komganative.komga_native"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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

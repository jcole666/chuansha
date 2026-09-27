import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ------------------------------------------------------------
// 签名配置：从 android/key.properties 读取（该文件不要提交到 git）
//
// key.properties 格式：
//   storeFile=/绝对路径/keystore.jks
//   storePassword=xxx
//   keyAlias=xxx
//   keyPassword=xxx
//
// 生成 keystore：
//   keytool -genkey -v -keystore ~/chuansha-release.jks \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias chuansha
//
// 读不到就返回 null —— 此时 release 退回 debug 签名（仅用于本地调试），
// 并会在构建日志里给出警告，避免"以为出了正式包其实签的是 debug key"。
// ------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.leneve.chuansha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.leneve.chuansha"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 打包的 ABI。
        // 之前只有 arm64-v8a：模拟器（x86_64）和部分老机型装不上。
        // 现在补 armeabi-v7a（32 位老机）与 x86_64（模拟器）。
        // 想要体积最小的话，发布时可用 --split-per-abi 出分包。
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "⚠️  未找到 android/key.properties，release 包将使用 debug 签名。" +
                        "请配置正式 keystore 后再发布到应用市场。"
                )
                signingConfigs.getByName("debug")
            }
            // 正式包关闭资源压缩歧义、保留行号便于线上排查
            isMinifyEnabled = false
            isShrinkResources = false
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

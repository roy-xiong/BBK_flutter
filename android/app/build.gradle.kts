import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// 本地忽略文件与 Actions Secrets 共用固定证书；缺少证书时 Release 必须失败。
val releaseProperties = Properties().apply {
    val source = rootProject.file("key.properties")
    if (source.exists()) source.inputStream().use { load(it) }
}
fun signingValue(local: String, environment: String): String? =
    releaseProperties.getProperty(local)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environment)?.takeIf { it.isNotBlank() }

android {
    namespace = "com.xiongjian.bbk_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.2.12479018"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.xiongjian.bbk_flutter"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        create("bbkRelease") {
            storeFile = signingValue("storeFile", "BBK_RELEASE_STORE_FILE")?.let { rootProject.file(it) }
            storePassword = signingValue("storePassword", "BBK_RELEASE_STORE_PASSWORD")
            keyAlias = signingValue("keyAlias", "BBK_RELEASE_KEY_ALIAS")
            keyPassword = signingValue("keyPassword", "BBK_RELEASE_KEY_PASSWORD")
            storeType = "JKS"
        }
    }
    buildTypes {
        debug { signingConfig = signingConfigs.getByName("bbkRelease") }
        release { signingConfig = signingConfigs.getByName("bbkRelease") }
    }
}
kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}
flutter { source = "../.." }

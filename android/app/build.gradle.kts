import org.gradle.api.tasks.Exec

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.daymark"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.daymark"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // 仓库未内置发布密钥：先用 debug 密钥签名，保证构建出的 APK 可直接安装。
            // 正式发布时改为读取 android/key.properties 中的发布密钥即可。
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

val rustDirectory = rootProject.projectDir.parentFile.resolve("rust")
val nativeLibraries = project.layout.projectDirectory.dir("src/main/jniLibs").asFile

tasks.register<Exec>("buildRustAndroid") {
    workingDir = rootProject.projectDir.parentFile
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-t", "x86_64",
        "-o", nativeLibraries.absolutePath,
        "build", "--release", "--manifest-path", rustDirectory.resolve("Cargo.toml").absolutePath,
    )
}

tasks.named("preBuild").configure {
    dependsOn("buildRustAndroid")
}

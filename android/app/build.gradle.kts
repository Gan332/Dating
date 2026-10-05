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
    // cargo-ndk 在派发构建前会先在当前目录执行 `cargo metadata` 定位 package，
    // 所以工作目录必须指向包含 Cargo.toml 的 rust/，不能只靠 --manifest-path
    // （否则报 “could not find Cargo.toml in ... or any parent directory”）。
    workingDir = rustDirectory
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-t", "x86_64",
        "-o", nativeLibraries.absolutePath,
        "build", "--release",
    )
    doLast {
        val missing = listOf("arm64-v8a", "armeabi-v7a", "x86_64").filter { abi ->
            val dir = nativeLibraries.resolve(abi)
            dir.listFiles()?.none { it.name.endsWith(".so") } ?: true
        }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "cargo ndk 未在 ${nativeLibraries.absolutePath} 生成 .so: $missing",
            )
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("buildRustAndroid")
}

// jniLibs 的合并/打包任务必须排在 Rust 产物生成之后，否则 APK 里会缺少 .so。
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }
    .configureEach { dependsOn("buildRustAndroid") }

import org.gradle.api.tasks.Exec

/**
 * 只打包真机用的两套 ABI：一个包里塞三套原生库会让 APK 直接大三倍
 * （实测 universal 59 MB vs 单 ABI 17~21 MB）。
 * 需要 x86_64 模拟器包时：`-PdaymarkAbis=arm64-v8a,armeabi-v7a,x86_64`。
 */
val targetAbis: List<String> =
    (project.findProperty("daymarkAbis") as String?)
        ?.split(",")
        ?.map(String::trim)
        ?.filter(String::isNotEmpty)
        ?.takeIf { it.isNotEmpty() }
        ?: listOf("arm64-v8a", "armeabi-v7a")

/** ABI → Rust 交叉编译三元组。 */
val rustTriples = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "armv7-linux-androideabi",
    "x86_64" to "x86_64-linux-android",
)

/**
 * AGP 不允许构建 AAB 时同时启用多 APK 拆包（issuetracker 402800800），
 * 所以按任务名判断：assemble 用拆包，bundle 关掉拆包。
 */
val isBundleBuild =
    gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }

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

    // 一个包里塞多套原生库会让 APK 直接变大好几倍（实测 59 MB vs 单 ABI 19 MB），
    // 所以同时产出 universal 与单 ABI 包；上架 AAB 时商店也会按 ABI 再分发。
    splits {
        abi {
            isEnable = !isBundleBuild
            reset()
            include(*targetAbis.toTypedArray())
            isUniversalApk = true
        }
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
    val args = mutableListOf("cargo", "ndk")
    for (abi in targetAbis) {
        args += listOf("-t", rustTriples[abi] ?: abi)
    }
    args += listOf("-o", nativeLibraries.absolutePath, "build", "--release")
    commandLine(*args.toTypedArray())
    doLast {
        val missing = targetAbis.filter { abi ->
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

import org.gradle.api.tasks.Exec
import java.util.Properties

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

/**
 * 发布签名：密钥与密码放在 android/key.properties（已由 .gitignore 排除，不进仓库）。
 * 文件不存在就回落 debug 签名 —— 任何人 clone 下来都能构建出可安装的 APK，
 * CI 上 fork/PR 拿不到 secrets 时走的也是这条路。
 */
val releaseKeyProperties = Properties().apply {
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) keyFile.inputStream().use { load(it) }
}
val hasReleaseKey = releaseKeyProperties.getProperty("storeFile") != null

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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // 相对路径按 app 模块目录解析，与 CI 写入 android/app/ 的位置对得上。
                storeFile = file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有 android/key.properties 就用发布密钥签名；没有就回落 debug，
            // 保证构建出的包仍可直接安装。上架必须走发布密钥那条路。
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

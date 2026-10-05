allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Gradle 默认的 buildDir 是 <repo>/android/build，而 Flutter 工具固定去
// <repo>/build/app/outputs/flutter-apk/ 找 APK。路径必须相对 projectDir：
// Kotlin DSL 里 buildDirectory.dir("../build") 是相对 buildDir 解析的，会得到
// android/build/../build（仍在 android/ 下），导致构建成功却找不到 APK。
val repoRoot = rootProject.layout.projectDirectory.dir("..")
val sharedBuildDir = repoRoot.dir("build")

rootProject.layout.buildDirectory.set(sharedBuildDir)

subprojects {
    project.layout.buildDirectory.set(sharedBuildDir.dir(project.name))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

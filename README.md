# 拾日 · Android 倒数日

Flutter Material 3 Expressive 风格界面 + Rust 日期核心的离线优先倒数日应用。用户事件保存在本机 SQLite；日历换算只在设备本地运行。项目目前提供 Android 构建配置。

## 功能

- 首页倒数卡片、月历和农历日期、二十四节气与传统节日标记。
- 自定义重要日、生日、目标和纪念日；支持一次、公历每年、农历每年及指定闰月。
- 卡片上直接显示「已经 2557 天」「第 7 周年」——不只是倒数，也回看已经走过的日子。
- 中国官方假期及调休上班日，联网时自动更新到最新年度；拉不到时继续用内置安排，不影响离线使用。只填入已公布的年度安排；新增年份数据时请以国务院办公厅通知为准。
- 可选本地提醒，默认关闭；提前天数可自选（0–365 天），时刻可为 0–23 点之间任意一小时。
- 重要日可按名称、备注或节日名搜索，也可按分类筛选；内置假期与传统节日一并参与搜索。
- 改完可以撤销上一步操作，批量修改与备份恢复同样可撤销。
- 备份可导出为 JSON 文件（交给系统分享面板保存）、从文件导入；也可复制到剪贴板临时转移。记录、内置条目改动与外观设置都在里面。
- Rust 核心负责公历有效性校验和跨日计算，通过 Dart FFI 调用。

## 运行

安装 Flutter 3.47 或更高（内含 Dart 3.13 或更高）、Rust stable、Android SDK/NDK，以及 cargo-ndk：

    cargo install cargo-ndk
    flutter create --platforms=android .
    flutter pub get
    flutter run

仓库不包含 Flutter 自动生成的 Gradle Wrapper 和 local.properties。首次运行 flutter create --platforms=android . 会补齐当前 Flutter 版本对应的 Android Wrapper/模板文件；之后由 Flutter 写入本机 SDK 路径。Gradle 的 preBuild 会通过 cargo-ndk 为 arm64-v8a、armeabi-v7a 和 x86_64 编译 Rust 动态库，并放入 Android jniLibs。首次构建需要可用的 crates.io 与 pub.dev 网络连接。

运行 Rust 核心测试：

    cargo test --manifest-path rust/Cargo.toml

运行 Flutter 单元测试与静态检查：

    flutter test
    flutter analyze

`test/event_store_test.dart` 会跑真实 SQLite，依赖 dev_dependencies 里的 `sqflite_common_ffi`。它通过 native assets 在本机编译 SQLite：Linux/macOS 直接可用；Windows 需要装 MSVC C++ 生成工具，否则会报找不到 sqlite3.dll。

## 构建 APK（GitHub Actions）

仓库自带工作流 `.github/workflows/build-apk.yml`：push 到 `main`、PR，或在 Actions 页面手动
Run workflow 都会触发。流程是 ubuntu + JDK 17 + Flutter stable + Rust 工具链，安装与
`flutter.ndkVersion` 一致的 Android NDK；先依次跑 `cargo test`、`flutter analyze`、
`flutter test` 三道检查，全部通过才执行 `flutter build apk --release` 与
`flutter build appbundle --release`，最后把 APK 与 AAB 作为 Artifacts 上传（保留 30 天），
可在该次运行页面下载。

release 版本当前使用 debug 密钥签名，便于直接安装验证；正式发布请换成自己的发布密钥。

2026 官方安排来源：国务院办公厅《国务院办公厅关于2026年部分节假日安排的通知》（国办发明电〔2025〕7号，2025-11-04）。未来年度安排需在正式通知发布后更新 lib/data/holiday_catalog.dart。

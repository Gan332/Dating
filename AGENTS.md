# AGENTS.md

拾日（daymark）：Flutter Material 3 Expressive + Rust 日期核心的离线优先倒数日应用，Android 端。

## 硬性约束

- 禁止使用 web search 工具，改用 Free search。
- 禁止使用 `print`，用 `debugPrint`（`analysis_options.yaml` 开启了 `avoid_print`）。
- 禁止引入需要网络或账号的服务；应用必须完全离线可用。
- 任何界面/交互改动都要在浏览器或设备上实际验证行为，不能只看一次渲染截图。

## 运行环境

- Flutter ≥ 3.47 / Dart ≥ 3.13，Rust stable，Android SDK/NDK，`cargo-ndk`。
- 仓库不提交 Gradle Wrapper 和 `local.properties`。首次使用跑 `flutter create --platforms=android .` 补齐模板，之后由 Flutter 写入本机 SDK 路径。

## 目录结构

```
lib/main.dart              入口与 M3EMaterialApp 配置
lib/app_controller.dart    ChangeNotifier 状态层，唯一的数据入口
lib/core/calendar_engine.dart  农历/节气/重复事件换算
lib/core/rust_date_core.dart   Rust FFI 封装（含纯 Dart 回退）
lib/data/event_store.dart      SQLite 读写、JSON 导入导出
lib/data/holiday_catalog.dart  国务院公布的假期与调休数据
lib/models/countdown_event.dart 事件模型与序列化
lib/services/reminder_service.dart 本地通知（可选能力）
lib/ui/app_shell.dart     主页框架与导航
lib/ui/event_editor.dart  事件编辑底部弹窗
rust/src/lib.rs           无依赖的公历日期核心，C ABI 导出
test/                     Flutter 单元测试
```

## 架构约定

- 状态集中在 `AppController`（`ChangeNotifier`），界面通过 `AnimatedBuilder` 订阅，不要在 Widget 里自己读 SQLite 或 SharedPreferences。
- `EventStore` 和 `ReminderScheduler` 都要支持注入假实现，测试才能不依赖平台通道。
- 所有跨插件/IO 的启动步骤都套 `_withTimeout`（10 秒上限），并且无论成败都要把 `_ready` 置为 true，避免界面永远卡在转圈。
- 提醒是可选功能：任何实现都不能把异常抛给调用方，失败只降级为「不提醒」。
- `CountdownEvent.toMap`/`fromMap` 是数据库 schema 和 JSON 备份的唯一契约；改字段要同步 `event_store.dart` 的建表语句并考虑旧备份的兼容性。
- `HolidayCatalog` 只收录国务院办公厅已公布的年度安排。新增年份必须依据正式通知更新数据、`publishedYear`、`source`、`sourceDate`。
- 日期比较一律走 `CalendarEngine.dateOnly` / `daysBetween`，不要直接减 `DateTime` 差值。

## Rust FFI

- 导出函数用 `#[no_mangle] pub extern "C"`，参数为基本类型，非法日期返回 `INVALID_DATE`（`i64::MIN`）。
- `RustDateCore` 只在 Android 上加载 `libdaymark_core.so`；符号缺失或加载失败时静默回退到纯 Dart 实现。新增导出函数时两边的签名 typedef 都要更新。
- Gradle 的 `preBuild` 和 `merge*JniLibFolders` 任务依赖 `buildRustAndroid`，它用 `cargo ndk` 为 arm64-v8a、armeabi-v7a、x86_64 构建并输出到 `android/app/src/main/jniLibs`。`workingDir` 必须指向 `rust/`（cargo-ndk 依赖当前目录找 `Cargo.toml`）。

## 验证流程

改动落地前跑通：

```
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
```

涉及界面的改动还要实际运行应用走一遍相关流程（增删改事件、切换重复类型、提醒开关、备份导入导出），并检查受影响的每个页面在改动的状态下表现一致。改布局或样式时桌面与移动视口都要看。

## 提交风格

提交信息使用中文，前缀为 `feat:` / `fix:` / `chore:` / `style:` / `docs:`。
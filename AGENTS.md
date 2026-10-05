# Repository Guidelines

拾日（`daymark`）：Flutter + Material 3 Expressive 界面、Rust 日期核心的倒数日应用，仅 Android。数据存本机 SQLite，日历换算全在设备本地完成；节假日安排支持联网刷新（唯一出网路径，失败静默降级到内置数据）。

## 硬性约束

- 禁止使用 web search 工具，改用 Free search。
- 禁止使用 `print`，用 `debugPrint`（`analysis_options.yaml` 开启了 `avoid_print`）。
- 应用必须完全离线可用：新增能力不得引入账号或强制联网。已有的 `HolidayRepository` 是唯一出网点，必须保持「拉不到就用缓存/内置数据、绝不阻塞启动」的行为。
- 任何界面/交互改动都要在浏览器或设备上实际验证行为，不能只看一次渲染截图。

## Architecture & Data Flow

```
lib/main.dart          AppController.load() ──▶ M3EMaterialApp(M3EThemeScope)
                                                       │ AnimatedBuilder
                                                       ▼
lib/ui/app_shell.dart  AppShell ─ IndexedStack ─▶ 首页 / 日历 / 重要日 / 设置
        │  所有改动走 _runMutation(动作, 文案) ──▶ SnackBar + 「撤销」
        ▼
lib/app_controller.dart  ChangeNotifier，唯一的写入口；每个动作 _remember(label) 存快照
        ├── EventStore        → SQLite daymark_events.db（events / day_overrides）
        ├── SettingsStore     → SharedPreferences `daymark.settings`（整段 JSON）
        ├── ReminderScheduler → flutter_local_notifications（可失败，降级为不提醒）
        └── HolidayRepository → 内置数据 + 缓存 + 联网覆盖层
```

关键数据流约定：

- **启动**：`load()` 里 `_withTimeout(_loadCore(), '读取本地数据')` 之后 `unawaited` 三件后台事（提醒预热、读节假日缓存、静默刷新），`finally` 无条件把 `_ready = true`。`_ready` 为 false 时 `main.dart` 显示 `_StartupView`，出错时 `AppShell` 顶部显示 `_StartupErrorBanner`。
- **写操作**：`saveEvent` / `deleteEvent(s)` / `updateEventsCategory` / `updateEventsReminder` / `saveOverride` / `restoreOverride(s)` / `updateSettings` / `setRemindersEnabled`。每个都先 `_remember(label)`，再落库，再 `_refresh()` 重读并重建提醒。
- **撤销**：`_UndoSnapshot` 存 events + overrides + settings，`undo()` 用 `EventStore.replaceAll` 全量回滚。
- **内置条目不落库**：官方节假日与传统节日由 `HolidayCatalog` / `lunar` 算出；用户改动以 `DayOverride` 行存储，靠稳定标识 `origin` 关联（`CalendarEngine.holidayOrigin(name, start)` → `holiday:春节:2026-02-15`；`festivalOrigin` → `festival:2026-02-17:名称`）。隐藏某条即 `hidden == 1`。
- **日期计算**：`CalendarEngine.daysBetween` → `RustDateCore.daysBetween`（Android 上走 `libdaymark_core.so`，否则走 `DateTime.utc` 差值）。禁止直接相减 `DateTime`。

## Key Directories

| 路径 | 用途 |
| --- | --- |
| `lib/main.dart` | 入口、`FlutterError.onError`、主题与启动页切换 |
| `lib/app_controller.dart` | `ChangeNotifier` 状态层 + 撤销 + 备份/恢复 |
| `lib/core/calendar_engine.dart` | `dateOnly` / `daysBetween` / `occurrences` / `nextOccurrence` / `approachProgress` / `milestoneFor` 与其中文文案函数、农历与节气、origin 构造、按日缓存 |
| `lib/data/backup_file_gateway.dart` | `BackupFileGateway` 抽象 + `PluginBackupFileGateway`（share_plus 导出 / file_picker 导入）、`backupFilename`、`BackupFileException` |
| `lib/core/rust_date_core.dart` | FFI 封装（`daymark_days_between` typedef + 纯 Dart 回退） |
| `lib/core/year_progress.dart` | 年度进度（`dayOfYear` / `totalDays` / `progress`） |
| `lib/data/event_store.dart` | SQLite 全部读写 + 备份载荷（`_schemaVersion = 3`，备份 `version = 2`，兼容读 v1；`EventStore({String? databasePath})` 供单测注入临时库） |
| `lib/data/settings_store.dart` | 设置 JSON 持久化 + 旧版 `remindersEnabled` 迁移 |
| `lib/data/holiday_catalog.dart` | 内置 2026 安排、`publishedYear`/`source`/`sourceDate`、`applyOnline`/`clearOnline` 覆盖层 |
| `lib/data/holiday_repository.dart` | `HttpClient` 拉取（raw → jsDelivr → timor 兜底）、SharedPreferences 缓存、`HolidayUpdateException` |
| `lib/models/` | `countdown_event.dart`、`day_override.dart`、`app_settings.dart`、`holiday_data.dart` |
| `lib/services/reminder_service.dart` | `ReminderScheduler` 抽象 + `ReminderService.instance` 单例实现 |
| `lib/ui/app_shell.dart` | 四个页面、导航、`_runMutation`、`BatchSelection`、动效组件 |
| `lib/ui/event_editor.dart` / `day_override_editor.dart` | 新增/编辑自带记录、改动内置条目（`DayOverrideResult.restore` 表示恢复默认） |
| `rust/src/lib.rs` | 无依赖公历核心，C ABI 导出 |
| `android/` | Gradle KTS + cargo-ndk 交叉编译任务 |
| `assets/holidays/holidays.json` | 线上数据源本体（`daymark.holidays` v1），**未**在 pubspec 声明为打包资源 |
| `test/` | 8 个单元测试文件 |

## Development Commands

```

flutter pub get
flutter analyze
flutter test
cargo test --manifest-path rust/Cargo.toml

cargo install cargo-ndk          # 首次需要
flutter create --platforms=android .   # 补齐被 gitignore 的 Gradle Wrapper

flutter run
flutter build apk --release --target-platform android-arm,android-arm64
flutter build appbundle --release --target-platform android-arm,android-arm64
```

需要 x86_64 模拟器包时追加 `-PdaymarkAbis=arm64-v8a,armeabi-v7a,x86_64`。

仓库不提交 Gradle Wrapper 与 `android/local.properties`（见 `.gitignore`），CI 也有专门步骤从 Flutter 缓存或临时 `flutter create` 项目里补 wrapper。

## Runtime & Tooling

- Flutter ≥ 3.47 / Dart ≥ 3.13，Rust stable，Android SDK + NDK（版本取 `flutter.ndkVersion`），JDK 17。
- 依赖（`pubspec.yaml`）：`flutter_local_notifications ^22.3.1`、`intl ^0.20.2`、`lunar ^1.7.8`、`material_3_expressive ^1.1.5`、`material_ui ^1.5.0`、`shared_preferences ^2.5.3`、`sqflite ^2.4.4`、`timezone ^0.11.1`；dev：`flutter_lints ^6.0.0`。
- Android：`namespace`/`applicationId` = `com.example.daymark`，`minSdk 23`、`compileSdk`/`targetSdk 36`、AGP 8.11.1、Kotlin 2.2.20、`multiDexEnabled`、core library desugaring。release 当前用 **debug 密钥**签名（仓库无 `android/key.properties`），发布前必须替换。
- `android/build.gradle.kts` 把 `buildDirectory` 重定向到仓库根 `build/`，因为 Flutter 固定去 `build/app/outputs/flutter-apk/` 找 APK。改 Gradle 路径时别动这条。
- `android/app/build.gradle.kts` 注册 `buildRustAndroid`（`Exec`）：`workingDir` 必须是 `rust/`（cargo-ndk 靠当前目录找 `Cargo.toml`），`cargo ndk -t … -o android/app/src/main/jniLibs build --release`，`doLast` 校验 `.so` 真的生成；`preBuild` 与 `merge*JniLibFolders` 依赖它。`splits.abi` 仅在非 bundle 任务启用（AGP 不允许 AAB 同时拆包）。
- CI：`.github/workflows/build-apk.yml`，`ubuntu-26.04`，JDK 17 + Flutter stable + Rust（aarch64/armv7/x86_64 Android target），先 `flutter analyze`、`flutter test` 再出包，APK/AAB 产物保留 30 天。

## Code Conventions & Common Patterns

- **中文注释与文案**，注释写在字段/函数上方说明「为什么」；所有面向用户的字符串是中文。
- **状态只在 `AppController`**：Widget 不直接碰 SQLite / SharedPreferences / 插件。UI 通过 `main.dart` 里的 `AnimatedBuilder` 或传入的 `onMutate` 回调交互。
- **依赖注入**：`AppController({EventStore? store, ReminderScheduler? reminders, SettingsStore? settingsStore, HolidayRepository? holidays, this.timeout = stepTimeout})`，测试注入假实现并调小 `timeout`。
- **超时兜底**：所有跨插件/IO 的启动步骤都套 `_withTimeout`（默认 `stepTimeout = 10s`）。
- **可选能力不抛错**：`ReminderService` 每个方法都 `try/catch` + `debugPrint`，失败即降级为「不提醒」；`AppController._rescheduleReminders` 再包一层。`HolidayRepository` 失败才抛 `HolidayUpdateException`（UI 只展示 `message`）。
- **错误处理分层**：数据不合法 → `throw const FormatException('中文说明')`；后台/可选路径 → `catch (error, stack) { debugPrint('…：$error\n$stack'); }`；需要 UI 感知 → `rethrow` 给 `_runMutation` 弹 SnackBar。
- **模型契约**：`CountdownEvent.toMap/fromMap`（`date` 存 `yyyy-MM-dd`）、`DayOverride.toMap/fromMap`（`date` 存 ISO8601，`hidden` 存 0/1）。改字段要同步 `event_store.dart` 的建表语句、`_schemaVersion` 与 `onUpgrade`，并考虑旧备份缺字段。
- **提醒时刻**：`CountdownEvent` / `DayOverride` 都有 `int reminderHour`（默认 9，0..23）。`fromMap` 必须写成 `((map['reminderHour'] as num?)?.toInt() ?? 9).clamp(0, 23)` —— 手改过的备份不能把 30 点这种非法值带进数据库。改内置条目提醒时，`AppController._reminderCandidates` 要把 `reminderHour` 一起搬进临时 `CountdownEvent`，否则时刻不生效。编辑器用 `event_editor.dart` 里的 `kReminderLeadOptions` 与 `formatHour`。
- **备份格式**：`{format: 'daymark.backup', version: 2, events: [...], overrides: [...], settings: {...}}`。`importPayload` 通过 `_readableBackupVersions = {1, 2}` 收口：继续接受 v1（缺字段回落到模型默认值），拒绝更高版本（字段语义未知，按老结构写会损坏数据）。全部校验必须保留：事件数 ≤ 1000、改动数 ≤ 2000、标题非空且 ≤ 80 字、id 不重复，且整个替换在 `database.transaction` 内。设置由 `AppController.exportJson` 补进载荷。
- **日期**：`CountdownEvent.dateKey` / `HolidayCatalog._key` 生成 `yyyy-MM-dd`；比较一律走 `CalendarEngine.dateOnly` / `daysBetween`。
- **里程碑文案**：`elapsedDays` 一律从事件最初的 `CountdownEvent.date` 起算，不是从今年重新计数。周年数公历重复按公历年、农历重复按**农历年**（`Lunar.getYear()` 之差；拿公历年差凑数会在腊月事件上错一整年）。`milestoneFor` 返回 `null` 或 `milestoneSummary` 返回空串时，界面整行隐藏，不要编数字出来。
- **内置条目的唯一算法在 `AppController.builtInOccurrences`**：首页与搜索都调它，别在 Widget 里再写一遍假期与农历节日，否则两处口径迟早不一致。
- **平台能力一律接口 + 构造注入**：`BackupFileGateway` 与 `ReminderScheduler` 同构。插件调用全部收口在 `PluginBackupFileGateway` 的两个静态方法里，插件签名对不上时只改那一个文件。导出返回 `false`、导入返回 `null` 都表示「用户取消」，不是错误。
- **提醒提前天数**：下拉里只有 0/1/7 是预设，其余算自定义。`kCustomLeadSentinel` 只是下拉项的占位值，**绝不能**存进数据库；合法范围 0–365。
- **Rust FFI**：导出用 `#[no_mangle] pub extern "C"`，非法日期返回 `INVALID_DATE`（`i64::MIN`）。Dart 侧 `RustDateCore.daysBetween` 只在 `Platform.isAndroid` 加载 `libdaymark_core.so`，符号缺失静默回退；新增导出时两边的 `_Native*` / `_Dart*` typedef 一起加。
- **Dart 语法坑**（已踩过）：条件表达式里不能用级联 `..`——`holiday_catalog.dart:110` 有注释说明，`makeupWorkdays` 改写成块函数体。
- **静态可变状态**：`HolidayCatalog._online` 是全局单例，测试必须在 `tearDown` 调 `HolidayCatalog.clearOnline`。
- **提交信息**：中文，前缀 `feat:` / `fix:` / `chore:` / `style:` / `docs:` / `perf:`。

## Testing & QA

`flutter test` + `cargo test`。CI 会在构建 APK 之前跑这两项，`flutter analyze` 也必须零告警（历史上专门清过 35 条 lint）。

现有测试（`flutter_test` 单元测试 + widget 测试，无 golden）：

| 文件 | 覆盖 |
| --- | --- |
| `test/app_controller_test.dart` | 启动成功/超时/抛错/重复 load、批量改动+撤销、恢复内置条目+撤销、设置持久化、备份含设置 |
| `test/app_controller_filter_test.dart` | `searchResults` 关键词/分类/叠加过滤、结果不可修改；导入失败不覆盖撤销快照的回归 |
| `test/event_store_test.dart` | 真实 SQLite（`sqflite_common_ffi`）：排序、全字段往返、精确删除/批量改、`replaceAll`、备份信封、多条拒绝路径、v1 兼容 |
| `test/reminder_time_test.dart` | `reminderHour` 缺字段回落 9、null、越界夹取、浮点截断、`copyWith` 不变异性 |
| `test/important_days_page_test.dart` | **widget 测试**：搜索/分类筛选/两者叠加/再点取消、两种空态的区分与文案、清除筛选 |
| `test/holiday_data_test.dart` | 自建数据格式与公共接口（timor）格式解析、坏数据返回 null、覆盖/清除内置数据 |
| `test/holiday_catalog_test.dart` | 2026 放假区间、补休日、未公布年份不推断、`latestYear` 不倒退（线上只剩更早年份时的回归守卫） |
| `test/calendar_engine_test.dart` | `daysBetween` 方向与闰日、过去的一次性事件仍可见、2/29 在平年收敛到 2/28、农历新年下一次；`lunarFestivalsInRange` 窗口边界 `[from, from+days)`、去重、不可修改；`approachProgress` 的 null/0/1/半程/夹取/闰日/农历 |
| `test/year_progress_test.dart` | 平年/闰年/跨年边界 |

写新测试时照抄 `test/app_controller_test.dart` 里的三个假实现（它们是文件私有的，新文件需重新声明）：

- `_FakeStore extends EventStore` —— `hangForever`（`await Completer().future` 模拟不返回）、`failOnRead`（抛 `StateError('数据库打不开')`）。
- `_FakeReminders extends ReminderService` 或 `implements ReminderScheduler` —— `hangForever`、`usable`、`initializeCalls`。
- `_FakeHolidays extends HolidayRepository` —— `super(endpoints: const <String>[])`，`fetch` 抛 `HolidayUpdateException('测试环境离线')`。**测试绝不联网。**

`setUp(() => SharedPreferences.setMockInitialValues({}))` 隔离设置；每个 `AppController` 测试结束显式 `controller.dispose()`。断言文案用中文 `test('…', …)`。

跑真实 SQL 的测试需要 `setUpAll` 里 `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`，并用 `Directory.systemTemp.createTempSync()` 给每个用例独立库文件；`tearDown` 必须先 `EventStore.close()` 再删目录，否则 Windows 上文件句柄占着删不掉，同一台机器连跑两次会读到上次的残留。`sqflite_common_ffi` 是 dev_dependency，删掉它 `test/event_store_test.dart` 就跑不起来。

widget 测试要 M3E 外壳（照抄 `lib/main.dart` 的 `M3EMaterialApp` + `M3EThemeScope`），列表在 `CustomScrollView` 里，断言某条记录前可能需要 `scrollUntilVisible`；夹具日期要远离当下，否则 upcoming/past 分段会随运行时间变化。

尚未覆盖：`ReminderService` 通知调度、`HolidayRepository._get` 的 HTTP 路径。

## Important Files

| 文件 | 为什么重要 |
| --- | --- |
| `lib/app_controller.dart` | 状态层；改字段要同步 UI getter 与撤销快照 |
| `lib/data/event_store.dart` | schema 与备份格式的唯一实现处 |
| `lib/models/countdown_event.dart` / `day_override.dart` | 序列化契约 |
| `lib/data/holiday_catalog.dart` | 新增年度须同时更新 `publishedYear`、`source`、`sourceDate` 与 `_spans`/`_makeupWorkdays`；来源见 README 末尾 |
| `assets/holidays/holidays.json` | 线上数据源本体，改格式要同步 `HolidayData.fromJson` |
| `android/app/build.gradle.kts` | cargo-ndk 任务与 ABI 策略 |
| `android/build.gradle.kts` | `buildDirectory` 重定向 |
| `.github/workflows/build-apk.yml` | 构建/测试的权威流程 |

## Verification

改动落地前跑通：

```
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
```

涉及界面的改动还要实际运行应用走一遍相关流程（增删改事件、切换重复类型、批量操作与撤销、提醒开关、备份复制/恢复、节假日刷新），并检查受影响的每个页面在改动的状态下表现一致。改布局或样式时桌面与移动视口都要看。

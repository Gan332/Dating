import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:daymark/ui/app_shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录存储的假实现：本页面只读，给一份固定列表即可。
class _FakeStore extends EventStore {
  _FakeStore(this.events);

  final List<CountdownEvent> events;

  @override
  Future<List<CountdownEvent>> allEvents() async => List.of(events);

  @override
  Future<List<DayOverride>> allOverrides() async => const [];
}

/// 提醒的假实现：不做任何事，免得测试碰通知插件通道。
class _FakeReminders implements ReminderScheduler {
  @override
  bool get available => true;

  @override
  Object? get lastError => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleEvents(List<CountdownEvent> events) async {}

  @override
  Future<void> cancelAll() async {}
}

/// 离线用的假数据源：测试里绝不联网。
class _FakeHolidays extends HolidayRepository {
  _FakeHolidays() : super(endpoints: const <String>[]);

  @override
  Future<HolidaySnapshot?> loadCached() async => null;

  @override
  Future<void> cache(HolidaySnapshot snapshot) async {}

  @override
  Future<HolidaySnapshot> fetch({required int year}) async =>
      throw const HolidayUpdateException('测试环境离线');
}

/// 固定的三条记录，跨年份各占一头，好让「接下来」和「已经走过」两段都有内容。
/// 备注里同时埋了中文词「花」和英文词 Marathon，分别用来验证跨分类搜索与
/// 忽略大小写。
final List<CountdownEvent> _fixture = [
  CountdownEvent(
    id: 'e1',
    title: '结婚纪念日',
    date: DateTime(2030, 5, 20),
    category: '纪念日',
    note: '南岸的花 · Anniversary',
  ),
  CountdownEvent(
    id: 'e2',
    title: '阿星生日',
    date: DateTime(2030, 8, 8),
    category: '生日',
    note: '小星星',
  ),
  CountdownEvent(
    id: 'e3',
    title: '年度目标',
    date: DateTime(2020, 1, 1),
    category: '目标',
    note: '花期 Marathon',
  ),
];

const String _wedding = '结婚纪念日';
const String _birthday = '阿星生日';
const String _goal = '年度目标';

/// M3EThemeController 自身不持有任何资源，整个文件共用一个。
final M3EThemeController _themeController = M3EThemeController();

AppController? _activeController;

/// 搭出与 main.dart 里 DaymarkApp 相同的 M3E 主题外壳，让 M3E 组件能拿到主题。
Widget _app(AppController controller, {VoidCallback? onAdd}) => M3EMaterialApp(
      debugShowCheckedModeBanner: false,
      data: M3EThemeData.light(seedColor: const Color(0xFF6750A4)),
      autoTheming: false,
      dynamicColoring: false,
      home: M3EThemeScope(
        baseData: M3EThemeData.light(seedColor: const Color(0xFF6750A4)),
        controller: _themeController,
        autoTheming: false,
        initialTheme: Brightness.light,
        dynamicColoring: false,
        child: Scaffold(
          body: SafeArea(
            child: ImportantDaysPage(
              controller: controller,
              onAdd: onAdd ?? () {},
              onEdit: (_) {},
              onDelete: (_) {},
              onMutate: (action, label) => action(),
            ),
          ),
        ),
      ),
    );

/// 起一个只喂内存数据的控制器。[timeout] 调小，免得插件通道无响应把用例拖死。
Future<AppController> _start(List<CountdownEvent> events) async {
  final controller = AppController(
    store: _FakeStore(events),
    reminders: _FakeReminders(),
    holidays: _FakeHolidays(),
    timeout: const Duration(milliseconds: 200),
  );
  await controller.load();
  _activeController = controller;
  return controller;
}

/// 放大到足够高的一屏：三条记录连同两段标题一次全部构建，
/// 断言「看不到某条」才真的是被筛掉了，而不是滚出了视口。
Future<void> _pump(
  WidgetTester tester,
  AppController controller, {
  VoidCallback? onAdd,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(controller, onAdd: onAdd));
  await tester.pumpAndSettle();
}

Finder _searchField() => find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '搜索名称、备注或节日',
      description: '搜索框',
    );

/// 分类筛选项：按类型定位，避开卡片副标题上同样写着分类名的 Text。
Finder _chip(String category) => find.widgetWithText(FilterChip, category);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_searchField(), text);
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String category) async {
  await tester.tap(_chip(category));
  await tester.pumpAndSettle();
}

void _expectVisible(String title) =>
    expect(find.text(title), findsOneWidget, reason: '应能看到「$title」');

void _expectHidden(String title) =>
    expect(find.text(title), findsNothing, reason: '不该再看到「$title」');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() {
    _activeController?.dispose();
    _activeController = null;
  });

  group('重要日页：搜索', () {
    testWidgets('没输搜索词时，三条记录的标题都在列表里', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      _expectVisible(_wedding);
      _expectVisible(_birthday);
      _expectVisible(_goal);
    });

    testWidgets('搜索命中标题：只剩标题里含关键词的那条', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '纪念');

      _expectVisible(_wedding);
      _expectHidden(_birthday);
      _expectHidden(_goal);
    });

    testWidgets('搜索也看备注：标题不含关键词仍能被搜出来', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '小星星');

      _expectVisible(_birthday);
      _expectHidden(_wedding);
      _expectHidden(_goal);
    });

    testWidgets('搜索忽略大小写：大写的英文关键词能命中备注里的原文', (
      tester,
    ) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, 'MARATHON');

      _expectVisible(_goal);
      _expectHidden(_wedding);
      _expectHidden(_birthday);
    });

    testWidgets('搜不到任何东西：给的是「没有符合条件的记录」空态', (
      tester,
    ) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '查无此条');

      expect(find.text('没有符合条件的记录'), findsOneWidget);
      expect(find.text('清除筛选'), findsOneWidget);
      // 记录还在，只是被筛空了，不该劝用户去新建。
      expect(find.text('添加一条'), findsNothing);
    });

    testWidgets('搜索词首尾的空白会被去掉', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '  花  ');

      _expectVisible(_wedding);
      _expectVisible(_goal);
      _expectHidden(_birthday);
    });
  });

  group('重要日页：分类筛选', () {
    testWidgets('点分类只留下该分类的记录', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _tapChip(tester, '纪念日');

      _expectVisible(_wedding);
      _expectHidden(_birthday);
      _expectHidden(_goal);
    });

    testWidgets('再点同一个分类即取消筛选，恢复完整列表', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _tapChip(tester, '生日');
      _expectVisible(_birthday);
      _expectHidden(_wedding);

      await _tapChip(tester, '生日');

      _expectVisible(_wedding);
      _expectVisible(_birthday);
      _expectVisible(_goal);
    });
  });

  group('重要日页：搜索与分类叠加', () {
    testWidgets('两个条件同时生效，只留下同时满足的记录', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '花');
      _expectVisible(_wedding);
      _expectVisible(_goal);
      _expectHidden(_birthday);

      await _tapChip(tester, '纪念日');

      _expectVisible(_wedding);
      _expectHidden(_goal);
      _expectHidden(_birthday);
    });
  });

  group('重要日页：两种空态', () {
    testWidgets('一条记录都没有：提示新建，并且按钮真的能唤起新建', (
      tester,
    ) async {
      var added = false;
      final controller = await _start(const []);
      await _pump(tester, controller, onAdd: () => added = true);

      expect(find.text('还没有自定义重要日'), findsOneWidget);
      expect(find.text('添加一条'), findsOneWidget);
      expect(find.text('没有符合条件的记录'), findsNothing);
      expect(find.text('清除筛选'), findsNothing);

      await tester.tap(find.text('添加一条'));
      await tester.pumpAndSettle();

      expect(added, isTrue, reason: '点「添加一条」应该回调新建');
    });

    testWidgets('有记录但被筛空：给的是「清除筛选」而不是新建入口', (
      tester,
    ) async {
      var added = false;
      final controller = await _start(_fixture);
      await _pump(tester, controller, onAdd: () => added = true);

      await _tapChip(tester, '其他');

      expect(find.text('没有符合条件的记录'), findsOneWidget);
      expect(find.text('添加一条'), findsNothing);
      _expectHidden(_wedding);

      // 选中一个没人用的分类同样走「被筛空」这条空态。
      await _type(tester, '查无此条');
      expect(find.text('没有符合条件的记录'), findsOneWidget);

      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();

      _expectVisible(_wedding);
      _expectVisible(_birthday);
      _expectVisible(_goal);
      expect(find.text('没有符合条件的记录'), findsNothing);
      expect(added, isFalse, reason: '清除筛选不该触发新建');
    });

    testWidgets('清掉筛选后，搜索框里的词也一并被清掉', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await _type(tester, '查无此条');
      expect(find.text('没有符合条件的记录'), findsOneWidget);

      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();

      expect(find.text('没有符合条件的记录'), findsNothing);
      expect(
        tester.widget<TextField>(_searchField()).controller?.text,
        isEmpty,
      );
      _expectVisible(_wedding);
    });
  });
}
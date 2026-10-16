import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:daymark/ui/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录存储的假实现：本页面只读，给一份固定列表即可。
class _FakeStore extends EventStore {
  _FakeStore(List<CountdownEvent> events, {List<String>? categories})
      : events = List.of(events),
        categories = categories ?? EventStore.defaultCategories;

  /// 记录列表。构造时**必须拷贝**一份进来：分类增删改会原地替换
  /// `events[index]`，若直接持有调用方给的那份列表，一个用例就会把全局夹具
  /// 改掉，后面用同一份夹具的用例全被污染——表现是单跑通过、连着跑失败。
  final List<CountdownEvent> events;

  /// 这个用例要用的分类清单；传 null 表示用内置的那几个。
  List<String> categories;

  @override
  Future<List<CountdownEvent>> allEvents() async => List.of(events);

  @override
  Future<List<DayOverride>> allOverrides() async => const [];

  @override
  Future<List<String>> allCategories() async => categories;

  // 分类增删改要真的落库：这些用例要验证面板走完之后控制器里确实多了一项，
  // 只读不写的话面板看起来能点，实际上什么都没发生。
  @override
  Future<void> replaceCategories(List<String> names) async {
    categories = List.of(names);
  }

  // 删分类时控制器会把挂在它上面的记录挪到「其他」，这条路径也必须留在内存里，
  // 否则会走到基类实现去真的开数据库。
  @override
  Future<void> updateEventsCategory(List<String> ids, String category) async {
    for (final (index, event) in [...events.indexed]) {
      if (ids.contains(event.id)) {
        events[index] = event.copyWith(category: category);
      }
    }
  }
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

  /// 测试环境没有系统权限可谈：精确闹钟一律当作拿不到，走不精确那条路。
  @override
  Future<bool> canScheduleExactly() async => false;

  @override
  Future<bool> requestExactAlarmsPermission() async => false;
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
Future<AppController> _start(
  List<CountdownEvent> events, {
  List<String>? categories,
}) async {
  final controller = AppController(
    store: _FakeStore(events, categories: categories),
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

/// 分类管理面板里某一行的某个按钮。
///
/// 每行有「改名」和「删除」两个 IconButton，只按行定位会命中两个；用
/// `find.byTooltip` 又会找到包在外面的 Tooltip 而不是按钮本身。直接按 IconButton
/// 的 tooltip 属性筛，拿到的是既能 tap 又能读 onPressed 的那一个。
Finder _categoryButton(String category, String tooltip) => find.descendant(
      of: find.widgetWithText(ListTile, category),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
        description: 'IconButton($tooltip)',
      ),
    );

/// 分类名同时出现在筛选条和卡片副标题上，断言筛选条时必须按类型定位，
/// 否则会数出两个一模一样的 Text。
void _expectChipVisible(String category) => expect(
      _chip(category),
      findsOneWidget,
      reason: '筛选条上应有「$category」',
    );

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

  group('重要日页：分类清单', () {
    testWidgets('筛选条列的是控制器里的分类，不是写死的那几个', (tester) async {
      final controller = await _start(
        _fixture,
        categories: ['纪念日', '旅行'],
      );
      await _pump(tester, controller);

      _expectChipVisible('纪念日');
      _expectChipVisible('旅行');
      // 用户删掉的分类不该还留在筛选条上。
      expect(_chip('目标'), findsNothing);
    });

    testWidgets('分类管理入口可见', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      expect(find.widgetWithText(ActionChip, '管理分类'), findsOneWidget);
    });

    testWidgets('打开管理面板后能新增分类，控制器里真的多了一项', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await tester.tap(find.widgetWithText(ActionChip, '管理分类'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '新增分类'),
        '旅行',
      );
      await tester.tap(find.widgetWithText(M3EButton, '添加'));
      await tester.pumpAndSettle();

      expect(controller.categories, contains('旅行'));
    });

    testWidgets('重名的分类在面板里就被挡下，不会有第二个「生日」', (
      tester,
    ) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await tester.tap(find.widgetWithText(ActionChip, '管理分类'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '新增分类'),
        '生日',
      );
      await tester.tap(find.widgetWithText(M3EButton, '添加'));
      await tester.pumpAndSettle();

      // 面板还开着（没被 pop 掉），并且给了一句说明。
      expect(find.widgetWithText(TextField, '新增分类'), findsOneWidget);
      expect(find.text('已经有「生日」这个分类了'), findsOneWidget);
      expect(controller.categories.where((name) => name == '生日'), hasLength(1));
    });

    testWidgets('删除分类要二次确认，确认后记录挪到「其他」', (tester) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await tester.tap(find.widgetWithText(ActionChip, '管理分类'));
      await tester.pumpAndSettle();

      await tester.tap(_categoryButton('目标', '删除分类'));
      await tester.pumpAndSettle();

      // 确认框先问一句，说明记录不会丢。
      expect(find.text('删除这个分类？'), findsOneWidget);
      expect(find.textContaining('挪到'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(controller.categories, isNot(contains('目标')));
    });

    testWidgets('「其他」的删除按钮是禁用的：它是记录挪过去的目的地', (
      tester,
    ) async {
      final controller = await _start(_fixture);
      await _pump(tester, controller);

      await tester.tap(find.widgetWithText(ActionChip, '管理分类'));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        _categoryButton('其他', '这个分类不能删'),
      );

      expect(button.onPressed, isNull);
      expect(await controller.deleteCategory('其他'), isFalse);
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
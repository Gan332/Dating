import 'dart:io';

import 'package:daymark/data/cover_store.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/ui/day_override_editor.dart';
import 'package:daymark/ui/event_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// 封面存取通道的假实现：`resolve` 一律返回 null（测试里不加载真实图片），
/// `save` 只是把「选中的源文件」原样交回，编辑器的其余行为不受文件系统影响。
class _FakeCoverStore implements CoverStore {
  const _FakeCoverStore();

  @override
  Future<String> save(String eventId, String sourcePath) async => sourcePath;

  @override
  Future<File?> resolve(String? filename) async => null;

  @override
  Future<void> remove(String? filename) async {}

  @override
  Future<void> removeOrphans(Set<String> keep) async {}
}

/// 两个编辑器共用的 M3E 主题外壳（照抄 main.dart 的层次）。
final M3EThemeController _themeController = M3EThemeController();

Widget _host(Widget child) => M3EMaterialApp(
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
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// 最近一次编辑器提交的结果；每个用例由打开函数清空。
CountdownEvent? savedEvent;
DayOverrideResult? savedOverride;

/// 默认 800×600 的测试窗口装不下整个表单，保存按钮会落在屏幕外，
/// 而 bottom sheet 里的滚动不是点击能依赖的东西（`ensureVisible` 在这里
/// 不可靠，按钮永远在折叠线以下）。把视口调高，编辑器完整可见。
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 把编辑器弹出来，参数与 app_shell 里的真实调用一致。
///
/// 不能用 `MaterialPageRoute`：编辑器自己不是 Scaffold，Material 祖先由
/// bottom sheet 提供，换成整页路由会直接撞上「No Material widget found」。
Future<void> _openEventEditor(
  WidgetTester tester, {
  CountdownEvent? event,
  Future<String?> Function(String id)? pick,
}) async {
  savedEvent = null;
  _useTallWindow(tester);
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            savedEvent = await showModalBottomSheet<CountdownEvent>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => EventEditor(
                event: event,
                coverStore: const _FakeCoverStore(),
                onPickCover: pick ?? (_) async => null,
              ),
            );
          },
          child: const Text('打开编辑器'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

const String _springOrigin = 'holiday:春节:2026-02-15';

Future<void> _openOverrideEditor(
  WidgetTester tester, {
  String? savedCoverPath,
  Future<String?> Function(String id)? pick,
}) async {
  savedOverride = null;
  _useTallWindow(tester);
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            savedOverride = await showModalBottomSheet<DayOverrideResult>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => DayOverrideEditor(
                origin: _springOrigin,
                title: '春节',
                date: DateTime(2026, 2, 17),
                subtitle: '2026 官方假期',
                overridden: savedCoverPath != null,
                savedCoverPath: savedCoverPath,
                coverStore: const _FakeCoverStore(),
                onPickCover: pick ?? (_) async => null,
              ),
            );
          },
          child: const Text('打开改动面板'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开改动面板'));
  await tester.pumpAndSettle();
}

/// 先确保目标在视野里再点。视口已调高，正常情况下 `ensureVisible` 什么都不用做；
/// 留着它是为了内容以后变高（加了字段）时，测试仍能尽力够到按钮。
Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('事件编辑器', () {
    testWidgets('选了封面再保存，结果带着文件名，回调拿到的是这条记录的 id', (tester) async {
      String? pickedFor;
      await _openEventEditor(tester, pick: (id) async {
        pickedFor = id;
        return 'picked.png';
      });

      expect(find.text('选择封面'), findsOneWidget);
      await _tapAndSettle(tester, '选择封面');

      // 选完之后入口换成「更换封面」，并给出「移除」；这两处状态就代表
      // 表单已经记住了新文件名。
      expect(find.text('更换封面'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '第一次见面');
      await _tapAndSettle(tester, '保存');

      expect(savedEvent, isNotNull);
      expect(savedEvent!.title, '第一次见面');
      expect(savedEvent!.coverPath, 'picked.png');
      // 新建记录的 id 在打开编辑器时就定下了；选图与落库必须用同一个，
      // 封面文件名才与记录对得上。
      expect(pickedFor, isNotNull);
      expect(savedEvent!.id, pickedFor);
    });

    testWidgets('取消选择保持原封面，不把已经有的那张清掉', (tester) async {
      final existing = CountdownEvent(
        id: 'e1',
        title: '旧名字',
        date: DateTime(2030, 1, 1),
        coverPath: 'old.png',
      );
      String? pickedFor;
      await _openEventEditor(
        tester,
        event: existing,
        pick: (id) async {
          pickedFor = id;
          return null;
        },
      );

      expect(find.text('更换封面'), findsOneWidget);
      await _tapAndSettle(tester, '更换封面');

      expect(pickedFor, 'e1');
      expect(find.text('更换封面'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await _tapAndSettle(tester, '保存');
      expect(savedEvent!.coverPath, 'old.png');
    });

    testWidgets('移除后保存，封面字段变成 null', (tester) async {
      final existing = CountdownEvent(
        id: 'e1',
        title: '旧名字',
        date: DateTime(2030, 1, 1),
        coverPath: 'old.png',
      );
      await _openEventEditor(tester, event: existing);

      await _tapAndSettle(tester, '移除');
      expect(find.text('选择封面'), findsOneWidget);

      await _tapAndSettle(tester, '保存');
      expect(savedEvent!.coverPath, isNull);
    });

    testWidgets('切到农历重复会多出闰月开关，保存不受影响', (tester) async {
      await _openEventEditor(tester, pick: (_) async => null);

      // 这条 ListTile 的墨水曾被面板根的底色盖住（debug 断言），现在它
      // 有自己的透明 Material：切过来只是多一个开关，不该有任何异常。
      await _tapAndSettle(tester, '农历');
      expect(find.text('按指定闰月重复'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '农历生日');
      await _tapAndSettle(tester, '保存');

      expect(savedEvent, isNotNull);
      expect(savedEvent!.title, '农历生日');
      expect(savedEvent!.recurrence, EventRecurrence.lunarYearly);
    });

    testWidgets('没接封面通道时不显示封面区块', (tester) async {
      await tester.pumpWidget(_host(const EventEditor()));
      await tester.pumpAndSettle();

      expect(find.text('封面'), findsNothing);
      expect(find.text('选择封面'), findsNothing);
    });
  });

  group('内置条目改动面板', () {
    testWidgets('已设的封面带得进来，换了之后跟着改动一起提交', (tester) async {
      String? pickedFor;
      await _openOverrideEditor(
        tester,
        savedCoverPath: 'old.png',
        pick: (id) async {
          pickedFor = id;
          return 'new.png';
        },
      );

      // 已改过的条目：接着显示原来那张，而不是退回「没有封面」。
      expect(find.text('更换封面'), findsOneWidget);
      await _tapAndSettle(tester, '更换封面');

      expect(pickedFor, _springOrigin);
      await _tapAndSettle(tester, '保存改动');

      expect(savedOverride, isNotNull);
      expect(savedOverride!.override.coverPath, 'new.png');
    });

    testWidgets('没设过封面时可以直接选一张，保存后带上', (tester) async {
      await _openOverrideEditor(tester, pick: (_) async => 'new.png');

      expect(find.text('选择封面'), findsOneWidget);
      await _tapAndSettle(tester, '选择封面');
      expect(find.text('更换封面'), findsOneWidget);

      await _tapAndSettle(tester, '保存改动');
      expect(savedOverride!.override.coverPath, 'new.png');
    });
  });
}

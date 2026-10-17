import 'dart:io';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/cover_picker.dart';
import 'package:daymark/data/cover_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假选择器：由用例决定「用户挑到了什么路径 / 怎么失败」，不碰平台通道。
class _FakePicker implements CoverPicker {
  _FakePicker(this._pick);

  final Future<String?> Function() _pick;
  int calls = 0;

  @override
  Future<String?> pickImagePath() {
    calls++;
    return _pick();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('插件实现的错误映射', () {
    test('用户取消返回 null，不当成失败', () async {
      final picker = PluginCoverPicker(pick: () async => null);
      expect(await picker.pickImagePath(), isNull);
    });

    test('插件给的本地路径原样返回', () async {
      const path = r'C:\相册\IMG_0001.jpg';
      final picker = PluginCoverPicker(pick: () async => path);
      expect(await picker.pickImagePath(), path);
    });

    test('选择器打不开时抛中文异常，并带上原始错误', () async {
      final error = PlatformException(code: 'PickFailed');
      final picker = PluginCoverPicker(pick: () async => throw error);

      await expectLater(
        picker.pickImagePath(),
        throwsA(
          isA<CoverPickException>()
              .having((e) => e.message, 'message', '打不开图片选择器，请重试。')
              .having((e) => e.cause, 'cause', same(error))
              .having((e) => e.toString(), 'toString', '打不开图片选择器，请重试。'),
        ),
      );
    });

    test('选择器自己抛的中文异常不会被二次包装', () async {
      final picker = PluginCoverPicker(
        pick: () async =>
            throw const CoverPickException('这张图片读不了，请换一张试试。'),
      );

      await expectLater(
        picker.pickImagePath(),
        throwsA(
          isA<CoverPickException>().having(
            (e) => e.message,
            'message',
            '这张图片读不了，请换一张试试。',
          ),
        ),
      );
    });
  });

  group('控制器与选择器之间的接缝', () {
    late Directory root;
    late DateTime clock;
    late FileCoverStore store;

    setUp(() {
      // 每个用例一个临时目录，真机上的私有目录由 path_provider 提供，这里注入。
      root = Directory.systemTemp.createTempSync('daymark-cover-pick-');
      clock = DateTime(2026, 10, 17, 9);
      store = FileCoverStore(
        rootDirectory: () async => root,
        now: () => clock,
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    AppController controllerWith(_FakePicker picker) => AppController(
          coverPicker: picker,
          covers: store,
          timeout: const Duration(milliseconds: 200),
        );

    /// 造一张「相册里的图」；放在 covers 之外，模拟用户选中的外部文件。
    File sourceImage(String name) {
      final file = File('${root.path}${Platform.pathSeparator}$name');
      file.writeAsBytesSync(const [7, 8, 9]);
      return file;
    }

    Directory coversDirectory() => Directory(
        '${root.path}${Platform.pathSeparator}${FileCoverStore.directoryName}');

    List<String> coverNames() {
      final directory = coversDirectory();
      if (!directory.existsSync()) return const [];
      return directory
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();
    }

    test('选中的图复制进私有目录，返回带记录 id 的文件名', () async {
      final controller = controllerWith(
        _FakePicker(() async => sourceImage('相册里的图.png').path),
      );

      final name = await controller.pickCover('e1');

      expect(name, 'e1-${clock.millisecondsSinceEpoch}.png');
      expect(coverNames(), [name]);
      expect(
        File('${coversDirectory().path}${Platform.pathSeparator}$name')
            .readAsBytesSync(),
        [7, 8, 9],
        reason: '内容要原样复制，界面拿去落库的只是文件名',
      );
      controller.dispose();
    });

    test('用户取消返回 null，目录里不留任何文件', () async {
      final picker = _FakePicker(() async => null);
      final controller = controllerWith(picker);

      expect(await controller.pickCover('e1'), isNull);
      expect(picker.calls, 1);
      expect(coverNames(), isEmpty);
      controller.dispose();
    });

    test('源文件读不到时抛中文异常，不让记录指向一张空图', () async {
      final controller = controllerWith(
        _FakePicker(() async => '${root.path}${Platform.pathSeparator}不存在.png'),
      );

      await expectLater(
        controller.pickCover('e1'),
        throwsA(
          isA<CoverStoreException>().having(
            (e) => e.message,
            'message',
            '这张图片读不到了，请重新选一张。',
          ),
        ),
      );
      expect(coverNames(), isEmpty);
      controller.dispose();
    });

    test('选择器失败原样冒泡，界面拿得到可展示的消息', () async {
      final controller = controllerWith(
        _FakePicker(() async => throw const CoverPickException('打不开图片选择器，请重试。')),
      );

      await expectLater(
        controller.pickCover('e1'),
        throwsA(
          isA<CoverPickException>().having(
            (e) => e.message,
            'message',
            '打不开图片选择器，请重试。',
          ),
        ),
      );
      controller.dispose();
    });
  });
}

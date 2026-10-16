import 'dart:io';

import 'package:daymark/data/cover_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DateTime clock;
  late FileCoverStore store;

  setUp(() {
    // 每个用例一个临时目录，互不干扰；clock 固定，文件名才是可断言的。
    root = Directory.systemTemp.createTempSync('daymark-cover-');
    clock = DateTime(2026, 10, 17, 9);
    store = FileCoverStore(
      rootDirectory: () async => root,
      now: () => clock,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 造一张「相册里的图」，返回它的路径。放在 covers 之外，模拟用户选的外部文件。
  File sourceImage(String name, {List<int> bytes = const [1, 2, 3]}) {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes);
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

  group('保存', () {
    test('落进 covers 子目录，文件名带记录 id 与时间戳，后缀跟着源文件', () async {
      final source = sourceImage('相册里的图.png');
      final name = await store.save('e1', source.path);

      expect(name, 'e1-${clock.millisecondsSinceEpoch}.png');
      expect(coverNames(), [name]);
      expect(
        File('${coversDirectory().path}${Platform.pathSeparator}$name')
            .readAsBytesSync(),
        [1, 2, 3],
        reason: '内容要原样复制过来',
      );
    });

    test('认不出的后缀按 jpg 存', () async {
      expect(await store.save('e1', sourceImage('raw.raw').path), endsWith('.jpg'));
      expect(await store.save('e2', sourceImage('没有后缀').path), endsWith('.jpg'));
      expect(await store.save('e3', sourceImage('怪.这不像后缀').path), endsWith('.jpg'));
    });

    test('记录 id 里的路径字符被换掉，不会跑出 covers 目录', () async {
      final name = await store.save('a/b\\c..d', sourceImage('x.jpg').path);
      expect(name, startsWith('a_b_c__d-'));
      expect(FileCoverStore.isSafeName(name), isTrue);
    });

    test('换图换名字：同一张图再存一次不会覆盖上一次的文件', () async {
      final source = sourceImage('x.png');
      final first = await store.save('e1', source.path);
      clock = clock.add(const Duration(seconds: 1));
      final second = await store.save('e1', source.path);

      expect(second, isNot(first), reason: '同名会让 Image.file 继续显示旧图');
      expect(coverNames(), [first, second]..sort());
    });

    test('源文件读不到时抛中文异常，而不是留下一条指向空文件的记录', () async {
      await expectLater(
        store.save('e1', '${root.path}${Platform.pathSeparator}不存在.png'),
        throwsA(
          isA<CoverStoreException>().having(
            (error) => error.message,
            'message',
            '这张图片读不到了，请重新选一张。',
          ),
        ),
      );
      expect(coverNames(), isEmpty);
    });
  });

  group('取回', () {
    test('按文件名拿回文件', () async {
      final name = await store.save('e1', sourceImage('x.png').path);
      final file = await store.resolve(name);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
    });

    test('没有封面、文件已不在、名字不合法，一律返回 null', () async {
      expect(await store.resolve(null), isNull);
      expect(await store.resolve(''), isNull);
      expect(await store.resolve('从来没存过.png'), isNull);
      // 手改过的备份可以塞这种名字进来，绝不能让它读到目录外。
      expect(await store.resolve('../outside.png'), isNull);
      expect(await store.resolve('sub/dir.png'), isNull);
      expect(await store.resolve(r'sub\dir.png'), isNull);
    });
  });

  group('删除与清理', () {
    test('remove 删掉指定文件，重复删或不存在的名字都安静返回', () async {
      final name = await store.save('e1', sourceImage('x.png').path);
      await store.remove(name);
      expect(coverNames(), isEmpty);

      await store.remove(name);
      await store.remove(null);
      await store.remove('../不合法.png');
    });

    test('removeOrphans 只留 keep 里的，别的一并删掉', () async {
      final keep = await store.save('e1', sourceImage('a.png').path);
      clock = clock.add(const Duration(seconds: 1));
      final orphan = await store.save('e2', sourceImage('b.png').path);

      await store.removeOrphans({keep});

      expect(coverNames(), [keep]);
      expect(await store.resolve(orphan), isNull);
    });

    test('清理不会碰目录里的子目录', () async {
      Directory('${coversDirectory().path}${Platform.pathSeparator}子目录')
          .createSync(recursive: true);
      await store.removeOrphans(const <String>{});

      expect(
        Directory('${coversDirectory().path}${Platform.pathSeparator}子目录')
            .existsSync(),
        isTrue,
      );
    });

    test('keep 为空时把封面全清掉（导入备份后的情形）', () async {
      await store.save('e1', sourceImage('a.png').path);
      clock = clock.add(const Duration(seconds: 1));
      await store.save('e2', sourceImage('b.png').path);

      await store.removeOrphans(const <String>{});

      expect(coverNames(), isEmpty);
    });
  });

  group('文件名安全性', () {
    test('带路径分隔符或 .. 的名字都不安全', () {
      expect(FileCoverStore.isSafeName('e1-123.png'), isTrue);
      expect(FileCoverStore.isSafeName('../x.png'), isFalse);
      expect(FileCoverStore.isSafeName('a/b.png'), isFalse);
      expect(FileCoverStore.isSafeName(r'a\b.png'), isFalse);
      expect(FileCoverStore.isSafeName('a..b.png'), isFalse);
    });
  });
}

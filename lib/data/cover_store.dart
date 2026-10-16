import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 封面图文件的存取通道，控制器只依赖这个接口。
///
/// 与 `CountdownEvent.coverPath` 的约定一致：对外只给**文件名**，不给绝对路径。
/// 应用私有目录在换机、重装、被系统迁移之后都会变，存绝对路径等于把图留在旧机器上。
abstract class CoverStore {
  /// 把 [sourcePath] 复制进私有目录，返回新的文件名。
  ///
  /// 源文件读不到时抛 [CoverStoreException]：调用方要能在落库之前停下来，
  /// 否则记录会指着一张永远显示不出来的图。
  Future<String> save(String eventId, String sourcePath);

  /// 按文件名取回文件；文件已经不在了或名字不合法时返回 null。
  Future<File?> resolve(String? filename);

  /// 删掉一张封面。文件本来就不在时安静返回。
  Future<void> remove(String? filename);

  /// 删掉不在 [keep] 里的所有封面文件。
  ///
  /// 换图、删记录、恢复默认、导入备份之后都会留下没人引用的文件，清理统一走这一条：
  /// 改动当时**不**删文件，否则「撤销」把记录还回来时图已经没了。
  Future<void> removeOrphans(Set<String> keep);
}

/// 封面的读写失败。UI 只展示 [message]，原始错误留在 [cause] 里。
class CoverStoreException implements Exception {
  const CoverStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 真实实现：文件落在 `getApplicationSupportDirectory()/covers/`。
///
/// 用 Support 目录而不是 Documents：封面是应用的内部数据，不该出现在用户可见的
/// 文档目录里，也不需要参与系统的媒体扫描。
class FileCoverStore implements CoverStore {
  FileCoverStore({
    Future<Directory> Function()? rootDirectory,
    DateTime Function()? now,
  })  : _rootDirectory = rootDirectory ?? _defaultRootDirectory,
        _now = now ?? DateTime.now;

  /// 目录来源与时钟都可注入：测试给临时目录与固定时刻，真机走 path_provider。
  final Future<Directory> Function() _rootDirectory;
  final DateTime Function() _now;

  /// 封面文件所在子目录名。
  static const String directoryName = 'covers';

  /// 认得出的图片后缀；其余的按 jpg 存（生成的名字只用于自己读回来）。
  static const Set<String> knownExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'gif',
    'bmp',
  };

  static Future<Directory> _defaultRootDirectory() =>
      getApplicationSupportDirectory();

  Future<Directory> _directory() async {
    final root = await _rootDirectory();
    final directory =
        Directory('${root.path}${Platform.pathSeparator}$directoryName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<String> save(String eventId, String sourcePath) async {
    try {
      if (!await File(sourcePath).exists()) {
        throw const CoverStoreException('这张图片读不到了，请重新选一张。');
      }
      final directory = await _directory();
      final name = _buildFilename(eventId, sourcePath);
      final target = File('${directory.path}${Platform.pathSeparator}$name');
      // 用户重选的正好是已经在用的那张（相册里再点一次同一张）时不必再复制。
      if (target.path != sourcePath) {
        await File(sourcePath).copy(target.path);
      }
      return name;
    } on CoverStoreException {
      rethrow;
    } catch (error, stack) {
      debugPrint('保存封面失败：$error\n$stack');
      throw CoverStoreException('保存封面失败，请重试。', error);
    }
  }

  @override
  Future<File?> resolve(String? filename) async {
    if (filename == null || filename.isEmpty) return null;
    if (!isSafeName(filename)) {
      // 手改过的备份可以塞一个 `../../` 之类的名字进来，一律当成「没有封面」。
      debugPrint('封面文件名不合法，按没有封面处理：$filename');
      return null;
    }
    final directory = await _directory();
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    return await file.exists() ? file : null;
  }

  @override
  Future<void> remove(String? filename) async {
    if (filename == null || filename.isEmpty || !isSafeName(filename)) return;
    try {
      final directory = await _directory();
      final file = File('${directory.path}${Platform.pathSeparator}$filename');
      if (await file.exists()) await file.delete();
    } catch (error) {
      // 删不掉不该影响记录本身：留下的孤儿会在下次启动清理时被扫掉。
      debugPrint('删除封面失败：$error');
    }
  }

  @override
  Future<void> removeOrphans(Set<String> keep) async {
    try {
      final directory = await _directory();
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (keep.contains(name)) continue;
        await entity.delete();
      }
    } catch (error, stack) {
      debugPrint('清理孤儿封面失败：$error\n$stack');
    }
  }

  /// `<记录 id>-<毫秒>.<后缀>`。
  ///
  /// 换图**必须**换名字：Flutter 的 `Image.file` 按「路径 + 尺寸」缓存，往同一个
  /// 路径上覆盖新图，界面上还是旧那张。时间戳顺手解决了重名。
  String _buildFilename(String eventId, String sourcePath) {
    final safeId = eventId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$safeId-${_now().millisecondsSinceEpoch}.${_extensionOf(sourcePath)}';
  }

  /// 从源路径猜后缀；认不出来就用 jpg——名字只给应用自己读回来用，
  /// 阶不后缀都不影响 `Image.file` 解码。
  String _extensionOf(String sourcePath) {
    final dot = sourcePath.lastIndexOf('.');
    if (dot < 0 || dot == sourcePath.length - 1) return 'jpg';
    final raw = sourcePath.substring(dot + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,5}$').hasMatch(raw)) return 'jpg';
    return knownExtensions.contains(raw) ? raw : 'jpg';
  }

  /// 文件名里不许出现路径分隔符与 `..`：备份是用户可以手改的文本。
  static bool isSafeName(String name) =>
      !name.contains('/') && !name.contains(r'\') && !name.contains('..');
}

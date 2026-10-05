import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// 备份文件的默认名，形如 `daymark-backup-2026-01-05.json`。
///
/// 日期必须补零到两位：用户在文件管理器里按名字排序时，`2026-1-5` 这种写法会排到
/// `2026-10-1` 后面，一眼看去就像旧备份。调用方在导出那一刻传入 [now]，
/// 本函数不读时钟，测试也就能钉死结果。
String backupFilename(DateTime now) {
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return 'daymark-backup-${now.year}-$month-$day.json';
}

/// 备份文件的读写通道，控制器只依赖这个接口。
///
/// 约定：用户取消不是错误——导出返回 `false`，导入返回 `null`，界面照常安静地
/// 什么都不做；真正做不成时抛 [BackupFileException]，消息是能直接展示给用户的中文，
/// 原始错误留在 [BackupFileException.cause] 里。
abstract class BackupFileGateway {
  /// 把备份文本交给系统，由用户自己挑位置保存；分享面板被直接关掉时返回 `false`。
  Future<bool> exportText(String content, {required String filename});

  /// 让用户挑一个备份文件并读出文本；用户取消时返回 `null`。
  Future<String?> importText();
}

/// 调用系统分享面板。抽出来是为了让测试注入假实现，不必触碰平台通道。
typedef BackupShareInvoker = Future<ShareResult> Function(ShareParams params);

/// 弹出系统文件选择器，返回用户选中文件的本地路径；用户取消时返回 `null`。
typedef BackupPickInvoker = Future<String?> Function();

/// 依赖插件的真实实现：`share_plus` 负责把文件交出去，`file_picker` 负责把文件收回来。
///
/// 注意：本类里的插件 API（share_plus 13.x 的 `SharePlus.instance` / `ShareParams`、
/// file_picker 13.x 的静态 `FilePicker.pickFiles`）写于无法执行 `pub get` 的环境，
/// 未在真机或编译中验证过。若插件大版本改动签名，只需要改本类的 [_share]、[_pick]
/// 两个钩子及其默认实现，接口和测试都不用动。
class PluginBackupFileGateway implements BackupFileGateway {
  PluginBackupFileGateway({
    BackupShareInvoker? share,
    BackupPickInvoker? pick,
  })  : _share = share ?? shareViaSystemSheet,
        _pick = pick ?? pickBackupFile;

  final BackupShareInvoker _share;
  final BackupPickInvoker _pick;

  /// 分享出去的 JSON 用的 MIME 类型。有些系统据此决定用哪个应用打开，
  /// 类型不对的话用户可能被塞进一个文本编辑器。
  static const String jsonMimeType = 'application/json';

  @override
  Future<bool> exportText(String content, {required String filename}) async {
    try {
      final result = await _share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(content),
              name: filename,
              mimeType: jsonMimeType,
            ),
          ],
          subject: '拾日备份',
          title: filename,
        ),
      );
      // 「平台把内容递出去了，但用户随后做了什么判断不了」也算完成：此时只有
      // 用户主动关掉面板才是没做完，此时不该让界面报成功。
      return result.status != ShareResultStatus.dismissed;
    } catch (error, stack) {
      debugPrint('导出备份文件失败：$error\n$stack');
      throw BackupFileException('导出备份文件失败，请重试。', error);
    }
  }

  @override
  Future<String?> importText() async {
    final path = await _pickPath();
    if (path == null) return null;
    return _readBackup(path);
  }

  /// 让用户挑一个文件；选择器本身打不开时翻译成给用户看的中文。
  Future<String?> _pickPath() async {
    try {
      return await _pick();
    } on BackupFileException {
      rethrow;
    } catch (error, stack) {
      debugPrint('选择备份文件失败：$error\n$stack');
      throw BackupFileException('打不开文件选择器，请重试。', error);
    }
  }

  /// 读出备份文本。空文件等同于用户没挑到内容：交给上层「取消」那条路，
  /// 比把空串送进 jsonDecode 再抛一个看不懂的格式错误要好。
  Future<String?> _readBackup(String path) async {
    try {
      final text = await File(path).readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (error, stack) {
      debugPrint('读取备份文件失败：$error\n$stack');
      throw BackupFileException('读取备份文件失败，请换一个文件试试。', error);
    }
  }

  /// 插件调用收口在这里：签名若有变动，改这一处即可。
  static Future<ShareResult> shareViaSystemSheet(ShareParams params) =>
      SharePlus.instance.share(params);

  /// 插件调用收口在这里：13.x 的 `pickFiles` 是静态方法，取消时返回空列表。
  static Future<String?> pickBackupFile() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择拾日备份文件',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked.isEmpty) return null;
    if (picked.first.path case final String path) return path;
    // 云端文件有时拿不到本地路径，这时读不了内容，只能明确让用户换一个，
    // 不能假装成用户取消了选择。
    throw const BackupFileException('这个备份文件读不了，请换一个文件试试。');
  }
}

/// 备份文件读写失败。UI 只展示 [message]，原始错误留在 [cause] 里。
class BackupFileException implements Exception {
  const BackupFileException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

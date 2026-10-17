import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// 挑一张图片的通道。
///
/// 与 `BackupFileGateway` 同构：插件调用收在 [PluginCoverPicker] 里，界面层只认
/// 这个接口。编辑器要能在测试里走完「选图 → 落盘 → 带回文件名」整条路，不碰平台通道。
abstract class CoverPicker {
  /// 让用户挑一张图，返回它在本机上的路径；用户取消时返回 `null`。
  ///
  /// 取消不是错误（返回 `null`），真正打不开选择器才抛 [CoverPickException]。
  Future<String?> pickImagePath();
}

/// 系统图片选择器被打开时返回的本地路径；用户取消时返回 `null`。
typedef CoverPickInvoker = Future<String?> Function();

/// 依赖 `file_picker` 的真实实现。
///
/// 与 `PluginBackupFileGateway` 同一个坑：插件大版本改签名时只改 [_pick] 的默认值，
/// 接口与调用方都不用动。
class PluginCoverPicker implements CoverPicker {
  PluginCoverPicker({CoverPickInvoker? pick}) : _pick = pick ?? pickImageFile;

  final CoverPickInvoker _pick;

  @override
  Future<String?> pickImagePath() async {
    try {
      return await _pick();
    } on CoverPickException {
      rethrow;
    } catch (error, stack) {
      debugPrint('选择封面图失败：$error\n$stack');
      throw CoverPickException('打不开图片选择器，请重试。', error);
    }
  }

  /// 插件调用收口在这里。`FileType.image` 让系统只列图片，也就不能同时传
  /// `allowedExtensions`（那是 `FileType.custom` 专用的参数）。
  static Future<String?> pickImageFile() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择封面图',
      type: FileType.image,
    );
    if (picked.isEmpty) return null;
    if (picked.first.path case final String path) return path;
    // 云端图片有时拿不到本地路径，读不到内容就只能让用户换一张，
    // 不能假装成用户取消了选择。
    throw const CoverPickException('这张图片读不了，请换一张试试。');
  }
}

/// 选择封面失败。UI 只展示 [message]，原始错误留在 [cause] 里。
class CoverPickException implements Exception {
  const CoverPickException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

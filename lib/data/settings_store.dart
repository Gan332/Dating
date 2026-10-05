import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// 设置以一份 JSON 存在 shared_preferences 里，导入导出时整段搬运即可。
class SettingsStore {
  static const String key = 'daymark.settings';

  /// 旧版本单独存过提醒开关，读取时顺手迁移。
  static const String legacyRemindersKey = 'remindersEnabled';

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return AppSettings.fromJson(decoded);
        }
      } catch (_) {
        // 设置读坏了就退回默认值，不要卡住启动。
      }
    }
    return AppSettings(
      remindersEnabled: preferences.getBool(legacyRemindersKey) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(settings.toJson()));
    await preferences.remove(legacyRemindersKey);
  }
}

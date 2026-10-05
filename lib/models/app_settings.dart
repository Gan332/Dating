/// 主题模式：跟随系统 / 始终浅色 / 始终深色。
enum AppThemeMode { system, light, dark }

/// 预设配色。种子色决定整套 Material 配色。
enum AppSeed {
  purple('拾日紫', 0xFF6750A4),
  indigo('静谧蓝', 0xFF3F5BA9),
  teal('青瓷绿', 0xFF00696E),
  amber('暖阳橙', 0xFFA2540A),
  rose('樱花粉', 0xFF9C4146),
  slate('石墨灰', 0xFF4F5B6B);

  const AppSeed(this.label, this.colorValue);

  /// 界面上展示的名字。
  final String label;

  /// 打包成 32 位 ARGB 的种子色。
  final int colorValue;
}

/// 应用设置：跟随记录一起导出，便于换机恢复。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seed = AppSeed.purple,
    this.useDynamicColor = false,
    this.remindersEnabled = false,
  });

  final AppThemeMode themeMode;
  final AppSeed seed;

  /// Android 12 及以上是否跟随系统取色。
  final bool useDynamicColor;

  /// 本地提醒总开关。
  final bool remindersEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppSeed? seed,
    bool? useDynamicColor,
    bool? remindersEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seed: seed ?? this.seed,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    );
  }

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'seed': seed.name,
        'useDynamicColor': useDynamicColor,
        'remindersEnabled': remindersEnabled,
      };

  /// 容错解析：字段缺失或不认识时退回默认值，不让坏数据卡住启动。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: _enumByName(
        AppThemeMode.values,
        json['themeMode'] as String?,
        AppThemeMode.system,
      ),
      seed: _enumByName(AppSeed.values, json['seed'] as String?, AppSeed.purple),
      useDynamicColor: json['useDynamicColor'] == true,
      remindersEnabled: json['remindersEnabled'] == true,
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}

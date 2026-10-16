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

/// 重要日页的排序方式。
///
/// 只作用于「重要日」页，首页固定按剩余天数——首页回答的是「最近要发生什么」，
/// 换个排序它就不再是那个仪表盘了。
///
/// 没有「按标题」：中文标题按码位排出来的顺序对用户没有意义（既不是拼音也不是
/// 笔画），要做就得引一个拼音库并配套约定，等真有人要再说。
enum AppSortMode {
  /// 最近发生的排最前。这是默认值，也是升级前的行为。
  upcoming('按剩余天数'),

  /// 新记的排最前；没有创建时间的老记录（`createdAt == 0`）排最后。
  createdAt('按创建时间'),

  /// 按分类清单的顺序分组，清单里没有的分类排最后。
  category('按分类');

  const AppSortMode(this.label);

  /// 界面上展示的名字。
  final String label;
}

/// 应用设置：跟随记录一起导出，便于换机恢复。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seed = AppSeed.purple,
    this.useDynamicColor = false,
    this.remindersEnabled = false,
    this.sortMode = AppSortMode.upcoming,
  });

  final AppThemeMode themeMode;
  final AppSeed seed;

  /// Android 12 及以上是否跟随系统取色。
  final bool useDynamicColor;

  /// 本地提醒总开关。
  final bool remindersEnabled;

  /// 重要日页的排序方式。
  final AppSortMode sortMode;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppSeed? seed,
    bool? useDynamicColor,
    bool? remindersEnabled,
    AppSortMode? sortMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seed: seed ?? this.seed,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      sortMode: sortMode ?? this.sortMode,
    );
  }

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'seed': seed.name,
        'useDynamicColor': useDynamicColor,
        'remindersEnabled': remindersEnabled,
        'sortMode': sortMode.name,
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
      // 老设置与旧备份都没有这个键；写坏的值也回落默认，界面照常能用。
      sortMode: _enumByName(
        AppSortMode.values,
        json['sortMode'] as String?,
        AppSortMode.upcoming,
      ),
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}

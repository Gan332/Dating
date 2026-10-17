import 'dart:math';

import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../data/cover_store.dart';
import '../models/countdown_event.dart';
import 'cover_field.dart';

/// 提醒提前量选项。[days] 与数据库里的 `reminderDays` 一一对应，-1 表示关闭。
///
/// 单独列出来是为了让编辑器与批量修改共用一份选项，避免两处各写一遍后
/// 文案对不上。
const List<({int days, String label})> kReminderLeadOptions = [
  (days: 0, label: '当天'),
  (days: 1, label: '提前 1 天'),
  (days: 7, label: '提前 7 天'),
];

/// 把 0..23 的小时数格式成「09:00」。
String formatHour(int hour) =>
    '${hour.toString().padLeft(2, '0')}:00';


/// 提醒下拉里「自定义天数」这一项的占位值。
///
/// `reminderDays` 是真实的提前天数（-1 关闭、0 当天、1、7…），用一个不与任何
/// 合法天数冲突的哨兵值来表示「用户想自己填」，避免把它误当成天数存进数据库。
const int kCustomLeadSentinel = -999;

/// 提前天数是否正好是下拉里的预设项。
bool _isPresetLead(int days) =>
    kReminderLeadOptions.any((option) => option.days == days);

/// 编辑器要用的分类清单。
///
/// 正在编辑的记录可能带着一个已经不在清单里的分类名（用户删掉了那个分类，
/// 记录本身还在）。这时把原名补回清单，用户改个名字的功夫里分类不该被顺手换掉。
/// 清单为空（启动那一瞬，或测试里没给）则回落内置清单。
List<String> categoryChoices(List<String>? given, String? current) {
  final base = (given == null || given.isEmpty) ? kEventCategories : given;
  if (current != null && current.isNotEmpty && !base.contains(current)) {
    return [...base, current];
  }
  return base;
}

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    this.event,
    this.categories,
    this.coverStore,
    this.onPickCover,
  });

  final CountdownEvent? event;

  /// 分类选项，由调用方传入（界面层应当传 `AppController.categories`）。
  ///
  /// 刻意不把 AppController 塞进这个 Widget：编辑器只负责收集表单值，
  /// 分类清单与其他设置一样是外部依赖，构造注入能让它在测试里脱离控制器
  /// 单独跑。留空时回落到 [kEventCategories]。
  final List<String>? categories;

  /// 封面存取通道与选图回调，由界面层从 [AppController] 转交。
  ///
  /// 两者缺一就不显示封面区块：编辑器单测、以后别处复用时不强求接上相册。
  final CoverStore? coverStore;
  final CoverPickCallback? onPickCover;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _customLeadController;
  late final String _id;
  late DateTime _date;
  late EventRecurrence _recurrence;
  late String _category;
  late int _reminderDays;
  late int _reminderHour;
  late bool _leapMonth;

  /// 当前表单上的封面文件名；`null` 表示这条记录没有封面。
  ///
  /// 选了图、点了移除都只改这里，跟「保存」一起提交。旧图不在这里删——撤销
  /// 要把记录连同封面一起还回来，文件留给启动清理处置（见 `CoverField` 注释）。
  late String? _coverPath;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    // 新建的记录也在打开编辑器时先定下 id：选封面要用它给文件命名，保存时
    // 再用同一个 id 落库，封面文件的归属才对得上。
    _id = event?.id ?? _generateId();
    _coverPath = event?.coverPath;
    _titleController = TextEditingController(text: event?.title ?? '');
    _noteController = TextEditingController(text: event?.note ?? '');
    _date = event?.date ?? DateTime.now();
    _recurrence = event?.recurrence ?? EventRecurrence.once;
    // 新建时默认落在清单的第一个分类；编辑时保留记录原本的分类。
    final choices = categoryChoices(widget.categories, event?.category);
    _category = event?.category ?? choices.first;
    _reminderDays = event?.reminderDays ?? -1;
    _reminderHour = event?.reminderHour ?? 9;
    _leapMonth = (event?.lunarMonth ?? 0) < 0;
    // 已经是自定义天数的记录，打开编辑器就该把这个数字显示出来，
    // 否则用户看到空白输入框会以为提醒没设置。
    _customLeadController = TextEditingController(
      text: _isPresetLead(_reminderDays) || _reminderDays < 0
          ? ''
          : _reminderDays.toString(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _customLeadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lunar = Lunar.fromDate(_date);
    final coverStore = widget.coverStore;
    final onPickCover = widget.onPickCover;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(widget.event == null ? '记下一个重要日' : '编辑重要日',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _titleController,
                  autofocus: widget.event == null,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：第一次见面',
                    prefixIcon: Icon(Icons.bookmark_add_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '写下这一天的名称'
                      : null,
                ),
                const SizedBox(height: 8),
                Text('日期', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _pickDate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_date.year}年${_date.month}月${_date.day}日',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text('农历${lunar.getMonthInChinese()}'
                            '${lunar.getDayInChinese()}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('重复方式', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                M3ESegmentedButton<EventRecurrence>(
                  segments: const [
                    M3ESegment(value: EventRecurrence.once, label: '一次'),
                    M3ESegment(value: EventRecurrence.solarYearly, label: '公历'),
                    M3ESegment(value: EventRecurrence.lunarYearly, label: '农历'),
                  ],
                  selected: {_recurrence},
                  onSelectionChanged: (selection) =>
                      setState(() => _recurrence = selection.first),
                ),
                if (_recurrence == EventRecurrence.lunarYearly) ...[
                  const SizedBox(height: 8),
                  // 同改动面板：面板根是带背景的 DecoratedBox，ListTile 的墨水
                  // 会被它盖住并触发 debug 断言，包一层透明 Material 安置墨水。
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('按指定闰月重复'),
                      subtitle: Text('农历${lunar.getMonthInChinese()}'
                          '${lunar.getDayInChinese()}；指定闰月当年缺失时跳过'),
                      trailing: M3ESwitch(
                        value: _leapMonth,
                        onChanged: (value) => setState(() => _leapMonth = value),
                      ),
                    ),
                  ),
                  Text(
                    '农历三十在当月没有三十时按廿九计算。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('分类', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final category
                        in categoryChoices(widget.categories, widget.event?.category))
                      ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _reminderDays,
                  decoration: const InputDecoration(
                    labelText: '提醒',
                    prefixIcon: Icon(Icons.notifications_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('关闭提醒')),
                    for (final option in kReminderLeadOptions)
                      DropdownMenuItem(
                        value: option.days,
                        child: Text(
                          '${option.label} ${formatHour(_reminderHour)}',
                        ),
                      ),
                    DropdownMenuItem(
                      value: kCustomLeadSentinel,
                      child: Text(
                        _reminderDays >= 0 && !kReminderLeadOptions
                                .any((option) => option.days == _reminderDays)
                            ? '自定义 · 提前 $_reminderDays 天'
                            : '自定义天数',
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    if (value == kCustomLeadSentinel) {
                      // 落进自定义分支时给个合理起点：30 天。
                      if (!_isPresetLead(_reminderDays)) {
                        _reminderDays = 30;
                      }
                      return;
                    }
                    _reminderDays = value ?? -1;
                  }),
                ),
                // 选了预设之外的天数才问具体是多少天，否则多一个没用的输入框。
                if (_reminderDays >= 0 && !_isPresetLead(_reminderDays)) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customLeadController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: '提前多少天提醒',
                      prefixIcon: Icon(Icons.event_repeat_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return '填一个 0 到 365 之间的天数';
                      final days = int.tryParse(text);
                      if (days == null) return '请填一个整数';
                      if (days < 0 || days > 365) return '最多提前 365 天';
                      return null;
                    },
                    onChanged: (value) {
                      final days = int.tryParse(value.trim());
                      if (days != null) setState(() => _reminderDays = days);
                    },
                  ),
                ],
                // 提醒时刻只在真的要提醒时才问，关闭提醒时显示它没有意义。
                if (_reminderDays >= 0) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _reminderHour,
                    decoration: const InputDecoration(
                      labelText: '提醒时刻',
                      prefixIcon: Icon(Icons.schedule_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var hour = 0; hour < 24; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(formatHour(hour)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _reminderHour = value ?? 9),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                // 封面是可选装饰，和备注一样摆在表单后半段；挑了图也只是
                // 改表单状态，跟着「保存」一起提交。
                if (coverStore != null && onPickCover != null) ...[
                  const SizedBox(height: 16),
                  CoverField(
                    store: coverStore,
                    filename: _coverPath,
                    onPick: () => onPickCover(_id),
                    onChanged: (name) => setState(() => _coverPath = name),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: M3EButton(
                    style: M3EButtonStyle.filled,
                    onPressed: _save,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded),
                        SizedBox(width: 8),
                        Text('保存'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await M3EDatePicker.show(
      context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 100),
      helpText: '选择重要日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (value != null) setState(() => _date = value);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final lunar = Lunar.fromDate(_date);
    var lunarMonth = lunar.getMonth().abs();
    if (_leapMonth) lunarMonth = -lunarMonth;
    final existing = widget.event;
    final event = CountdownEvent(
      id: _id,
      title: _titleController.text.trim(),
      date: DateTime(_date.year, _date.month, _date.day),
      recurrence: _recurrence,
      category: _category,
      note: _noteController.text.trim(),
      lunarMonth: _recurrence == EventRecurrence.lunarYearly ? lunarMonth : null,
      lunarDay: _recurrence == EventRecurrence.lunarYearly ? lunar.getDay() : null,
      reminderDays: _reminderDays,
      reminderHour: _reminderHour,
      // 编辑已有记录时把创建时间原样带过去：0 意味着「未知」，落库时会补成保存那一刻，
      // 那会让一条 2019 年的记录看起来像今天才建的，按创建时间排序时直接跳到最前。
      createdAt: existing?.createdAt ?? 0,
      // 封面用的是表单里当前那一张：换了就是新图，移除过就是 null。
      coverPath: _coverPath,
    );
    Navigator.pop(context, event);
  }

  /// 新建记录的 id：时间戳 + 随机数，撞不上也不带任何用户信息。
  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1000000)}';
}

import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../models/countdown_event.dart';
import '../models/day_override.dart';
import 'event_editor.dart';

/// 编辑内置条目（官方节假日 / 传统节日）的结果。
///
/// [restore] 为 true 表示用户选择「恢复默认」，即清除已有改动。
class DayOverrideResult {
  const DayOverrideResult(this.override, {this.restore = false});

  final DayOverride override;
  final bool restore;
}

/// 内置条目的改动面板。保存后只记录改动，不影响内置数据本身。
class DayOverrideEditor extends StatefulWidget {
  const DayOverrideEditor({
    super.key,
    required this.origin,
    required this.title,
    required this.date,
    required this.subtitle,
    required this.overridden,
  });

  /// 内置条目的稳定标识。
  final String origin;

  /// 当前显示的名称（可能已经是改动后的）。
  final String title;

  final DateTime date;

  /// 原始说明，例如「2026 官方假期」。
  final String subtitle;

  /// 是否已经改过。
  final bool overridden;

  @override
  State<DayOverrideEditor> createState() => _DayOverrideEditorState();
}

class _DayOverrideEditorState extends State<DayOverrideEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _date;
  late String _category;
  late int _reminderDays;
  late int _reminderHour;
  late final TextEditingController _customLeadController;
  late bool _hidden;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _noteController = TextEditingController();
    _date = widget.date;
    _category = '重要日';
    _reminderDays = -1;
    _reminderHour = 9;
    _hidden = false;
    // 改动面板总是从「没有提醒」开始，数字输入框也就从空开始。
    _customLeadController = TextEditingController();
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
              Text(widget.overridden ? '改动内置条目' : '改动这条内置条目',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 6),
              Text(
                widget.overridden ? '${widget.title} · ${widget.subtitle}' : widget.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '名称',
                  prefixIcon: Icon(Icons.edit_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text('日期', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, color: colors.primary),
                      const SizedBox(width: 12),
                      Text(
                        '${_date.year}年${_date.month}月${_date.day}日',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('分类', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in kEventCategories)
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
                    if (!kReminderLeadOptions
                        .any((option) => option.days == _reminderDays)) {
                      _reminderDays = 30;
                    }
                    return;
                  }
                  _reminderDays = value ?? -1;
                }),
              ),
              // 选了预设之外的天数才问具体是多少天。
              if (_reminderDays >= 0 &&
                  !kReminderLeadOptions
                      .any((option) => option.days == _reminderDays)) ...[
                const SizedBox(height: 12),
                TextField(
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
                  onChanged: (value) {
                    final days = int.tryParse(value.trim());
                    if (days != null && days >= 0 && days <= 365) {
                      setState(() => _reminderDays = days);
                    }
                  },
                ),
              ],
              // 关闭提醒时不问时刻，跟事件编辑器保持一致。
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
              TextField(
                controller: _noteController,
                maxLines: 2,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hidden,
                onChanged: (value) => setState(() => _hidden = value),
                title: const Text('在列表里隐藏这条'),
                subtitle: const Text('隐藏后可随时恢复默认'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.overridden)
                    TextButton(
                      onPressed: _restore,
                      child: const Text('恢复默认'),
                    ),
                  const Spacer(),
                  M3EButton(
                    style: M3EButtonStyle.filled,
                    onPressed: _save,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded),
                        SizedBox(width: 8),
                        Text('保存改动'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (value != null) setState(() => _date = value);
  }

  void _restore() =>
      Navigator.pop(context, DayOverrideResult(_build(), restore: true));

  void _save() => Navigator.pop(context, DayOverrideResult(_build()));

  DayOverride _build() {
    final title = _titleController.text.trim();
    return DayOverride(
      origin: widget.origin,
      title: title.isEmpty ? widget.title : title,
      date: DateTime(_date.year, _date.month, _date.day),
      category: _category,
      note: _noteController.text.trim(),
      reminderDays: _reminderDays,
      reminderHour: _reminderHour,
      hidden: _hidden,
    );
  }
}

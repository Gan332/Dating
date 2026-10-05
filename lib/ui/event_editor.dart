import 'dart:math';

import 'package:lunar/lunar.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../models/countdown_event.dart';

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, this.event});

  final CountdownEvent? event;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _date;
  late EventRecurrence _recurrence;
  late String _category;
  late int _reminderDays;
  late bool _leapMonth;

  static const _categories = ['纪念日', '生日', '目标', '重要日', '其他'];

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleController = TextEditingController(text: event?.title ?? '');
    _noteController = TextEditingController(text: event?.note ?? '');
    _date = event?.date ?? DateTime.now();
    _recurrence = event?.recurrence ?? EventRecurrence.once;
    _category = event?.category ?? '纪念日';
    _reminderDays = event?.reminderDays ?? -1;
    _leapMonth = (event?.lunarMonth ?? 0) < 0;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lunar = Lunar.fromDate(_date);
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('按指定闰月重复'),
                    subtitle: Text('农历${lunar.getMonthInChinese()}'
                        '${lunar.getDayInChinese()}；指定闰月当年缺失时跳过'),
                    trailing: M3ESwitch(
                      value: _leapMonth,
                      onChanged: (value) => setState(() => _leapMonth = value),
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
                    for (final category in _categories)
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
                  items: const [
                    DropdownMenuItem(value: -1, child: Text('关闭提醒')),
                    DropdownMenuItem(value: 0, child: Text('当天 09:00')),
                    DropdownMenuItem(value: 1, child: Text('提前 1 天 09:00')),
                    DropdownMenuItem(value: 7, child: Text('提前 7 天 09:00')),
                  ],
                  onChanged: (value) =>
                      setState(() => _reminderDays = value ?? -1),
                ),
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
      id: existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}-'
          '${Random.secure().nextInt(1000000)}',
      title: _titleController.text.trim(),
      date: DateTime(_date.year, _date.month, _date.day),
      recurrence: _recurrence,
      category: _category,
      note: _noteController.text.trim(),
      lunarMonth: _recurrence == EventRecurrence.lunarYearly ? lunarMonth : null,
      lunarDay: _recurrence == EventRecurrence.lunarYearly ? lunar.getDay() : null,
      reminderDays: _reminderDays,
    );
    Navigator.pop(context, event);
  }
}

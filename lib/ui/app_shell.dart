import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/calendar_engine.dart';
import '../data/holiday_catalog.dart';
import '../models/countdown_event.dart';
import 'event_editor.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  Future<void> _editEvent([CountdownEvent? event]) async {
    final result = await showModalBottomSheet<CountdownEvent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventEditor(event: event),
    );
    if (result != null) await widget.controller.saveEvent(result);
  }

  Future<void> _deleteEvent(CountdownEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('“${event.title}”将从本机日历中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteEvent(event.id);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        controller: widget.controller,
        onAdd: () => _editEvent(),
        onEdit: _editEvent,
        onDelete: _deleteEvent,
      ),
      CalendarPage(controller: widget.controller, onEdit: _editEvent),
      ImportantDaysPage(
        controller: widget.controller,
        onAdd: () => _editEvent(),
        onEdit: _editEvent,
        onDelete: _deleteEvent,
      ),
      SettingsPage(controller: widget.controller),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      floatingActionButton: _tab == 3
          ? null
          : M3EExtendedFab(
              onPressed: () => _editEvent(),
              icon: const Icon(Icons.add_rounded),
              label: '记下重要日',
            ),
      bottomNavigationBar: M3ENavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          M3ENavigationBarDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: '拾日',
          ),
          M3ENavigationBarDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: '日历',
          ),
          M3ENavigationBarDestination(
            icon: Icon(Icons.bookmarks_outlined),
            label: '重要日',
          ),
          M3ENavigationBarDestination(
            icon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final AppController controller;
  final VoidCallback onAdd;
  final ValueChanged<CountdownEvent> onEdit;
  final ValueChanged<CountdownEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = CalendarEngine.dateOnly(now);
    final occurrences = <EventOccurrence>[];
    for (final event in controller.events) {
      final occurrence = CalendarEngine.nextOccurrence(event, today);
      if (occurrence != null && occurrence.daysRemaining >= 0) {
        occurrences.add(occurrence);
      }
    }
    for (final span in HolidayCatalog.spansForYear(today.year)) {
      if (!span.end.isBefore(today)) {
        final date = span.start.isBefore(today) ? today : span.start;
        occurrences.add(EventOccurrence(
          title: span.name,
          date: date,
          daysRemaining: CalendarEngine.daysBetween(today, date),
          subtitle: '${HolidayCatalog.publishedYear} 官方假期',
        ));
      }
    }
    for (var offset = 0; offset <= 180; offset++) {
      final date = today.add(Duration(days: offset));
      final names = CalendarEngine.lunarFestivals(date).toSet();
      for (final name in names) {
        if (name.isEmpty) continue;
        occurrences.add(EventOccurrence(
          title: name,
          date: date,
          daysRemaining: offset,
          subtitle: '传统节日',
        ));
      }
    }
    final customKeys = occurrences
        .where((item) => item.event != null)
        .map((item) => '${item.title}:${CountdownEvent.dateKey(item.date)}')
        .toSet();
    final unique = <String, EventOccurrence>{};
    for (final item in occurrences) {
      final contentKey = '${item.title}:${CountdownEvent.dateKey(item.date)}';
      if (item.event case final event?) {
        unique['event:${event.id}'] = item;
      } else if (!customKeys.contains(contentKey)) {
        unique.putIfAbsent(contentKey, () => item);
      }
    }
    final upcoming = unique.values.toList()
      ..sort((a, b) {
        final comparison = a.daysRemaining.compareTo(b.daysRemaining);
        if (comparison != 0) return comparison;
        return a.title.compareTo(b.title);
      });
    final dateText = '${now.year}年${now.month}月${now.day}日';

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      Icons.hourglass_bottom_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('拾日', style: Theme.of(context).textTheme.titleLarge),
                      Text(dateText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                    ],
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: '添加重要日',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                '把重要的日子，好好记住。',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.6,
                    ),
              ),
              const SizedBox(height: 20),
              _HeroCountdown(
                occurrence: upcoming.isEmpty ? null : upcoming.first,
                onAdd: onAdd,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _QuickStat(
                      icon: Icons.bookmark_rounded,
                      value: controller.events.length.toString(),
                      label: '件重要日',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickStat(
                      icon: controller.remindersEnabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      value: controller.remindersEnabled ? '开启' : '关闭',
                      label: '本地提醒',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('接下来',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const Spacer(),
                  Text('节日 · 纪念日',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const SizedBox(height: 12),
              if (upcoming.isEmpty)
                _EmptyEvents(onAdd: onAdd)
              else
                for (final item in upcoming.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OccurrenceTile(
                      occurrence: item,
                      onEdit: item.event == null ? null : () => onEdit(item.event!),
                      onDelete:
                          item.event == null ? null : () => onDelete(item.event!),
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                '节假日安排仅展示已公布的官方年度数据。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCountdown extends StatelessWidget {
  const _HeroCountdown({required this.occurrence, required this.onAdd});

  final EventOccurrence? occurrence;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = occurrence;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .45)!],
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: item == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Colors.white),
                const SizedBox(height: 22),
                const Text('留一个位置，给值得期待的事',
                    style: TextStyle(color: Colors.white, fontSize: 19)),
                const SizedBox(height: 6),
                const Text('创建你的第一条重要日',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 18),
                M3EButton(
                  style: M3EButtonStyle.tonal,
                  onPressed: onAdd,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded),
                      SizedBox(width: 8),
                      Text('现在添加'),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.subtitle,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    Text(
                      '${item.date.month.toString().padLeft(2, '0')}/'
                      '${item.date.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.daysRemaining == 0
                          ? '今天'
                          : item.daysRemaining.toString(),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: -2,
                          ),
                    ),
                    if (item.daysRemaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Text('天后',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white70,
                                )),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    value: .42,
                    minHeight: 5,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('每一天，都在靠近',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  const _QuickStat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 21),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({
    required this.occurrence,
    this.onEdit,
    this.onDelete,
  });

  final EventOccurrence occurrence;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = occurrence.date;
    final daysRemaining = occurrence.daysRemaining;
    final event = occurrence.event;
    final recurrenceLabel = event == null
        ? ''
        : switch (event.recurrence) {
            EventRecurrence.once => '',
            EventRecurrence.solarYearly => ' · 公历每年',
            EventRecurrence.lunarYearly => ' · 农历每年',
          };
    final subtitle = occurrence.subtitle + recurrenceLabel;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(date.month.toString().padLeft(2, '0'),
                        style: Theme.of(context).textTheme.labelSmall),
                    Text(date.day.toString(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(occurrence.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    daysRemaining == 0 ? '今天' : daysRemaining.abs().toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: daysRemaining < 0
                          ? colors.onSurfaceVariant
                          : colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (daysRemaining != 0)
                    Text(
                      daysRemaining > 0 ? '天后' : '天前',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.event_available_rounded, size: 32),
              const SizedBox(height: 10),
              const Text('还没有自定义重要日'),
              const SizedBox(height: 8),
              M3EButton(
                style: M3EButtonStyle.text,
                onPressed: onAdd,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded),
                    SizedBox(width: 8),
                    Text('添加一条'),
                  ],
                ),
              ),
            ],
          ),
        ),
  );
}

class ImportantDaysPage extends StatelessWidget {
  const ImportantDaysPage({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final AppController controller;
  final VoidCallback onAdd;
  final ValueChanged<CountdownEvent> onEdit;
  final ValueChanged<CountdownEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final today = CalendarEngine.dateOnly(DateTime.now());
    final occurrences = controller.events
        .map((event) => CalendarEngine.nextOccurrence(event, today))
        .whereType<EventOccurrence>()
        .toList();
    final upcoming = occurrences
        .where((item) => item.daysRemaining >= 0)
        .toList()
      ..sort((a, b) {
        final byDate = a.daysRemaining.compareTo(b.daysRemaining);
        return byDate != 0 ? byDate : a.title.compareTo(b.title);
      });
    final past = occurrences
        .where((item) => item.daysRemaining < 0)
        .toList()
      ..sort((a, b) {
        final byDate = b.daysRemaining.compareTo(a.daysRemaining);
        return byDate != 0 ? byDate : a.title.compareTo(b.title);
      });

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
          sliver: SliverList.list(
            children: [
              Text(
                '重要日',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                '你亲手记下的纪念日、生日和目标',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.upcoming_rounded, size: 17),
                    label: Text('即将到来 ${upcoming.length}'),
                  ),
                  if (past.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.history_rounded, size: 17),
                      label: Text('已过去 ${past.length}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (occurrences.isEmpty) ...[
                _EmptyEvents(onAdd: onAdd),
              ] else ...[
                if (upcoming.isNotEmpty) ...[
                  _SectionHeading(
                    title: '接下来',
                    count: upcoming.length,
                  ),
                  const SizedBox(height: 10),
                  for (final item in upcoming) ...[
                    _OccurrenceTile(
                      occurrence: item,
                      onEdit: item.event == null
                          ? null
                          : () => onEdit(item.event!),
                      onDelete: item.event == null
                          ? null
                          : () => onDelete(item.event!),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SectionHeading(title: '已经走过', count: past.length),
                  const SizedBox(height: 10),
                  for (final item in past) ...[
                    _OccurrenceTile(
                      occurrence: item,
                      onEdit: item.event == null
                          ? null
                          : () => onEdit(item.event!),
                      onDelete: item.event == null
                          ? null
                          : () => onDelete(item.event!),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.controller, required this.onEdit});

  final AppController controller;
  final ValueChanged<CountdownEvent> onEdit;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = CalendarEngine.dateOnly(now);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final start = DateTime(_month.year, _month.month, 1);
    final gridStart = start.subtract(Duration(days: (start.weekday + 6) % 7));
    final selectedLunar = Lunar.fromDate(_selected);
    final festivals = CalendarEngine.lunarFestivals(_selected);
    final term = CalendarEngine.solarTerm(_selected);
    final holiday = HolidayCatalog.holidayName(_selected);
    final isMakeupWorkday = HolidayCatalog.isMakeupWorkday(_selected);
    final onThisDate = widget.controller.events
        .where((event) => _eventOccursOn(event, _selected))
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('日历',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '上个月',
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('${_month.year}年${_month.month}月',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                    Text(
                      _month.year == HolidayCatalog.publishedYear
                          ? '已载入官方放假与调休安排'
                          : '传统节日可查 · 官方调休安排未载入',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '下个月',
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map((label) => Expanded(
                      child: Center(
                        child: Text(label,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 6,
            child: GridView.builder(
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 54,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, index) {
                final date = gridStart.add(Duration(days: index));
                final inMonth = date.month == _month.month;
                final selected = CalendarEngine.dateOnly(date) == _selected;
                final isToday = CalendarEngine.dateOnly(date) ==
                    CalendarEngine.dateOnly(DateTime.now());
                final hasEvent = widget.controller.events
                    .any((event) => _eventOccursOn(event, date));
                final hasHoliday = HolidayCatalog.holidayName(date) != null;
                final isMakeupWorkday = HolidayCatalog.isMakeupWorkday(date);
                final hasMarker = hasEvent || hasHoliday || isMakeupWorkday ||
                    CalendarEngine.lunarFestivals(date).isNotEmpty ||
                    CalendarEngine.solarTerm(date).isNotEmpty;
                return InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => setState(() => _selected = date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? colors.primaryContainer : null,
                      border: isToday && !selected
                          ? Border.all(color: colors.primary.withValues(alpha: .55))
                          : null,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(date.day.toString(),
                            style: TextStyle(
                              color: !inMonth
                                  ? colors.onSurface.withValues(alpha: .35)
                                  : selected
                                      ? colors.onPrimaryContainer
                                      : colors.onSurface,
                              fontWeight: isToday || selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            )),
                        const SizedBox(height: 2),
                        Text(CalendarEngine.lunarDayLabel(date),
                            maxLines: 1,
                            style: TextStyle(
                              color: !inMonth
                                  ? colors.onSurface.withValues(alpha: .27)
                                  : hasHoliday
                                      ? colors.error
                                      : isMakeupWorkday
                                          ? colors.tertiary
                                          : colors.onSurfaceVariant,
                              fontSize: 9,
                            )),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasMarker)
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: hasEvent || isMakeupWorkday
                                      ? colors.tertiary
                                      : colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (isMakeupWorkday) ...[
                              const SizedBox(width: 2),
                              Text(
                                '班',
                                style: TextStyle(
                                  color: colors.tertiary,
                                  fontSize: 8,
                                  height: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${_selected.month}月${_selected.day}日',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                        const SizedBox(width: 10),
                        Text('农历${selectedLunar.getMonthInChinese()}'
                            '${selectedLunar.getDayInChinese()}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                )),
                      ],
                    ),
                    if (holiday != null || isMakeupWorkday) ...[
                      const SizedBox(height: 10),
                      _DetailPill(
                        icon: isMakeupWorkday
                            ? Icons.work_outline_rounded
                            : Icons.celebration_rounded,
                        label: isMakeupWorkday
                            ? '调休上班'
                            : '${holiday!}假期',
                        color: isMakeupWorkday
                            ? colors.tertiary
                            : colors.error,
                      ),
                    ],
                    if (term.isNotEmpty || festivals.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          if (term.isNotEmpty)
                            _DetailPill(
                              icon: Icons.wb_sunny_outlined,
                              label: term,
                              color: colors.primary,
                            ),
                          for (final festival in festivals.take(3))
                            _DetailPill(
                              icon: Icons.local_florist_outlined,
                              label: festival,
                              color: colors.secondary,
                            ),
                        ],
                      ),
                    ],
                    for (final event in onThisDate)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.bookmark_rounded, color: colors.tertiary),
                        title: Text(event.title),
                        subtitle: Text(event.category),
                        trailing: IconButton(
                          tooltip: '编辑',
                          onPressed: () => widget.onEdit(event),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    if (holiday == null && !isMakeupWorkday &&
                        festivals.isEmpty && term.isEmpty && onThisDate.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('这一天还没有标记',
                            style: TextStyle(color: colors.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _eventOccursOn(CountdownEvent event, DateTime date) {
    final selected = CalendarEngine.dateOnly(date);
    if (event.recurrence == EventRecurrence.once) {
      return CalendarEngine.dateOnly(event.date) == selected;
    }
    return CalendarEngine.occurrences(event, selected, limit: 4)
        .any((occurrence) => occurrence == selected);
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 40),
        children: [
          Text('设置',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('本地提醒'),
              subtitle: const Text('默认关闭 · 09:00 提醒 · 不需要网络'),
              trailing: M3ESwitch(
                value: controller.remindersEnabled,
                onChanged: (value) async {
                  final enabled = await controller.setRemindersEnabled(value);
                  if (!context.mounted) return;
                  if (!enabled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请在系统设置中允许通知后重试。')),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制 JSON 备份'),
                  subtitle: const Text('备份保存在剪贴板，可粘贴到安全位置'),
                  onTap: () => _copyBackup(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('从剪贴板恢复'),
                  subtitle: const Text('恢复会替换本机当前的自定义记录'),
                  onTap: () => _restoreBackup(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_available_rounded),
                      const SizedBox(width: 12),
                      Text('中国节假日数据',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('当前内置 2026 年放假与调休上班安排。'),
                  const SizedBox(height: 5),
                  Text('${HolidayCatalog.source}（${HolidayCatalog.sourceDate}）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 8),
                  Text('其他年份只显示农历节日与节气；官方放假日期待正式公布后更新。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('拾日  ·  把时间留给重要的事',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
        ],
      );

  Future<void> _copyBackup(BuildContext context) async {
    final value = await controller.exportJson();
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON 备份已复制到剪贴板。')),
    );
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final data = await Clipboard.getData('text/plain');
    final source = data?.text;
    if (source == null || source.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板中没有可用的备份。')),
      );
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('替换本机记录？'),
        content: const Text('恢复备份会覆盖当前所有自定义重要日。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final count = await controller.importJson(source);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢复$count条记录。')),
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取备份，请确认内容完整。')),
      );
    }
  }
}

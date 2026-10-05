import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/calendar_engine.dart';
import '../data/holiday_catalog.dart';
import '../models/app_settings.dart';
import '../models/countdown_event.dart';
import '../core/year_progress.dart';
import 'day_override_editor.dart';
import 'event_editor.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.onRetry});

  final AppController controller;

  /// 启动出错时横幅上的重试回调。
  final VoidCallback? onRetry;

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
    if (result == null) return;
    await _runMutation(
      () => widget.controller.saveEvent(result),
      '已保存「${result.title}」',
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 所有改动的统一入口：出错弹提示，成功弹一条可撤销的提示。
  Future<void> _runMutation(
    Future<void> Function() action,
    String label,
  ) async {
    try {
      await action();
      if (!mounted) return;
      final controller = widget.controller;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          action: controller.canUndo
              ? SnackBarAction(label: '撤销', onPressed: _undoLast)
              : null,
        ),
      );
    } catch (error) {
      _showError('$label失败：$error');
    }
  }

  Future<void> _undoLast() async {
    try {
      await widget.controller.undo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已撤销上一步改动')),
      );
    } catch (error) {
      _showError('撤销失败：$error');
    }
  }

  /// 编辑一条自带记录。
  Future<void> _editEventRecord(CountdownEvent event) async {
    final result = await showModalBottomSheet<CountdownEvent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventEditor(event: event),
    );
    if (result == null) return;
    await _runMutation(
      () => widget.controller.saveEvent(result),
      '已保存「${result.title}」',
    );
  }

  /// 统一入口：自带记录走完整编辑器，内置条目走改动面板。
  Future<void> _editOccurrence(EventOccurrence item) async {
    if (item.event case final event?) {
      await _editEventRecord(event);
      return;
    }
    final origin = item.origin;
    if (origin == null) return;
    final result = await showModalBottomSheet<DayOverrideResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DayOverrideEditor(
        origin: origin,
        title: item.title,
        date: item.date,
        subtitle: item.subtitle,
        overridden: item.overridden,
      ),
    );
    if (result == null) return;
    if (result.restore) {
      await _runMutation(
        () => widget.controller.restoreOverride(origin),
        '已恢复「${item.title}」的默认安排',
      );
    } else {
      await _runMutation(
        () => widget.controller.saveOverride(result.override),
        '已保存对「${result.override.title}」的改动',
      );
    }
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
    if (confirmed != true) return;
    await _runMutation(
      () => widget.controller.deleteEvent(event.id),
      '已删除「${event.title}」',
    );
  }

  /// 内置条目的「删除」即清除改动，回到公布时的状态。
  Future<void> _deleteOccurrence(EventOccurrence item) async {
    if (item.event case final event?) {
      await _deleteEvent(event);
      return;
    }
    final origin = item.origin;
    if (origin == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复内置数据？'),
        content: Text('「${item.title}」会回到公布时的名称、日期与提醒设置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runMutation(
      () => widget.controller.restoreOverride(origin),
      '已恢复「${item.title}」的默认安排',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        controller: widget.controller,
        onAdd: () => _editEvent(),
        onEdit: _editOccurrence,
        onDelete: _deleteOccurrence,
        onMutate: _runMutation,
        onOpenAll: () => setState(() => _tab = 2),
      ),
      CalendarPage(controller: widget.controller, onEdit: _editEventRecord),
      ImportantDaysPage(
        controller: widget.controller,
        onAdd: () => _editEvent(),
        onEdit: _editOccurrence,
        onDelete: _deleteOccurrence,
        onMutate: _runMutation,
      ),
      SettingsPage(controller: widget.controller, onMutate: _runMutation),
    ];
    final loadError = widget.controller.loadError;
    return Scaffold(
      body: Column(
        children: [
          if (loadError != null)
            _StartupErrorBanner(
              message: loadError,
              onRetry: widget.onRetry,
            ),
          Expanded(
            child: SafeArea(
              child: IndexedStack(
                index: _tab,
                children: [
                  for (var index = 0; index < pages.length; index++)
                    _TabTransition(visible: index == _tab, child: pages[index]),
                ],
              ),
            ),
          ),
        ],
      ),
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
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMutate,
    this.onOpenAll,
  });

  final AppController controller;
  final VoidCallback onAdd;
  final ValueChanged<EventOccurrence> onEdit;
  final ValueChanged<EventOccurrence> onDelete;
  final MutationRunner onMutate;

  /// 首页条目多到一屏放不下时，点「查看全部」跳到重要日页。
  final VoidCallback? onOpenAll;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BatchSelection _selection = BatchSelection();

  /// 首页最多铺多少条。超过这个数就在末尾给一个「查看全部」入口，
  /// 而不是静悄悄地截断——用户无法知道自己漏看了什么。
  static const int _homeListLimit = 12;

  /// 当前列表里可见的条目，批量操作按它取选中项。
  List<EventOccurrence> _visible = const [];

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onAdd = widget.onAdd;
    final now = DateTime.now();
    final today = CalendarEngine.dateOnly(now);
    // 内置条目交给控制器统一算，首页与搜索共用同一份口径。
    final occurrences = <EventOccurrence>[
      for (final event in controller.events)
        if (CalendarEngine.nextOccurrence(event, today)
            case final occurrence?
            when occurrence.daysRemaining >= 0)
          occurrence,
      ...controller.builtInOccurrences(today),
    ];
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
    _visible = upcoming;
    final dateText = '${now.year}年${now.month}月${now.day}日';

    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
            sliver: SliverList.list(
            children: [
              if (_selection.active)
                _SelectionBar(
                  count: _selection.countIn(upcoming),
                  onCategory: _batchCategory,
                  onReminder: _batchReminder,
                  onDelete: _batchDelete,
                  onClose: () => setState(_selection.clear),
                )
              else
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
                        Text('拾日',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(dateText,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
                today: today,
                onAdd: onAdd,
              ),
              const SizedBox(height: 12),
              _Entrance(index: 1, child: _YearCountdownCard(now: now)),
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
              else ...[
                // 首页不再截断：全部列出来，超过一屏就继续往下滚。
                for (final (index, item) in upcoming.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _Entrance(
                      index: index + 2,
                      child: _OccurrenceTile(
                        occurrence: item,
                        selectionMode: _selection.active,
                        selected: _selection.contains(item),
                        onEdit: () => _handleTap(item),
                        onLongPress: () =>
                            setState(() => _selection.select(item)),
                        onDelete: () => widget.onDelete(item),
                      ),
                    ),
                  ),
                if (upcoming.length > _homeListLimit)
                  Center(
                    child: TextButton(
                      onPressed: widget.onOpenAll,
                      child: Text('还有 ${upcoming.length - _homeListLimit} 条，查看全部'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                '长按条目可多选批量改动。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  void _handleTap(EventOccurrence item) {
    if (_selection.active) {
      setState(() => _selection.toggle(item));
      return;
    }
    widget.onEdit(item);
  }

  Future<void> _batchCategory() async {
    final ids = _selection.eventIdsOf(_visible);
    if (ids.isEmpty) {
      _toast('批量改分类只对自己的记录生效');
      return;
    }
    final category = await showCategoryPicker(context);
    if (category == null) return;
    await widget.onMutate(
      () => widget.controller.updateEventsCategory(ids, category),
      '已把 ${ids.length} 条改为「$category」',
    );
    _clearSelection();
  }

  Future<void> _batchReminder() async {
    final ids = _selection.eventIdsOf(_visible);
    if (ids.isEmpty) {
      _toast('批量改提醒只对自己的记录生效');
      return;
    }
    final days = await showReminderPicker(context);
    if (days == null) return;
    await widget.onMutate(
      () => widget.controller.updateEventsReminder(ids, days),
      '已更新 ${ids.length} 条的提醒',
    );
    _clearSelection();
  }

  Future<void> _batchDelete() async {
    final ids = _selection.eventIdsOf(_visible);
    final origins = _selection.originsOf(_visible);
    if (ids.isEmpty && origins.isEmpty) return;
    final confirmed = await confirmBulkDelete(context, ids.length + origins.length);
    if (confirmed != true) return;
    await widget.onMutate(
      () async {
        if (ids.isNotEmpty) await widget.controller.deleteEvents(ids);
        if (origins.isNotEmpty) await widget.controller.restoreOverrides(origins);
      },
      '已删除 ${ids.length} 条、恢复 ${origins.length} 条内置安排',
    );
    _clearSelection();
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(_selection.clear);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
class _HeroCountdown extends StatelessWidget {
  const _HeroCountdown({
    required this.occurrence,
    required this.today,
    required this.onAdd,
  });

  final EventOccurrence? occurrence;

  /// 进度条要以「今天」为基准算，所以由调用方传入，避免卡片内部再取一次时间。
  final DateTime today;

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
                    AnimatedSwitcher(
                      duration: M3EMotion.medium1,
                      child: Text(
                        item.daysRemaining == 0
                            ? '今天'
                            : item.daysRemaining.toString(),
                        key: ValueKey(item.daysRemaining),
                        style:
                            Theme.of(context).textTheme.displayLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: -2,
                                ),
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
                // 已经过去多少天、第几周年。倒数日应用最打动人的是「相伴多久」，
                // 算不出来时整行不出现。
                if (_milestoneOf(item) case final text?) ...[
                  const SizedBox(height: 6),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
                // 只有年度重复的事件算得出真实进度；一次性事件与内置条目
                // 没有「上一次」可依，这时不画进度条，也不显示配套文案，
                // 免得给出一个与数据无关的数字。
                if (_progressOf(item) case final progress?) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: progress),
                      duration: M3EMotion.extraLong1,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一个周期已走过 ${(progress * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }

  /// 这条倒计时的真实进度；算不出来时返回 null，调用方据此隐藏进度条。
  double? _progressOf(EventOccurrence item) {
    final event = item.event;
    if (event == null) return null;
    return CalendarEngine.approachProgress(event, item.date, today);
  }

  /// 里程碑文案（已过天数 + 周年）；算不出来时返回 null，调用方据此整行隐藏。
  String? _milestoneOf(EventOccurrence item) {
    final event = item.event;
    if (event == null) return null;
    final milestone = CalendarEngine.milestoneFor(event, item.date);
    if (milestone == null) return null;
    final text = CalendarEngine.milestoneSummary(milestone);
    return text.isEmpty ? null : text;
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
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final EventOccurrence occurrence;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

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
    final reminderDays = occurrence.reminderDays;
    final subtitle = occurrence.subtitle +
        recurrenceLabel +
        (reminderDays >= 0 ? ' · 已提醒' : '');

    // 只有自带记录才有「从最初那一天算起」的意义：内置条目的 date 就是它
    // 本身，算出来只会是一句没有信息量的「今天就是这一天」。
    final milestone = event == null
        ? null
        : CalendarEngine.milestoneFor(event, date);
    return _Pressable(
      child: Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onEdit,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onEdit?.call(),
                )
              else
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    // 已经过去多少天、第几周年——只有自带记录算得出来，
                    // 内置条目的 date 就是它本身，算出来只会是「今天就是这一天」。
                    if (milestone case final text?) ...[
                      const SizedBox(height: 2),
                      Text(text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                  )),
                    ],
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
              if (onDelete != null && !selectionMode)
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(
                      value: 'delete',
                      child:
                          Text(occurrence.origin == null ? '删除' : '恢复默认'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
/// 列表空态。[filtered] 为真表示记录本身存在、只是被搜索或分类筛掉了，
/// 这时不该再劝用户去新建一条。
class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.onAdd, this.onClearFilter, this.filtered = false});

  final VoidCallback onAdd;

  /// 清除筛选条件的回调；为空表示当前不是被筛空的状态。
  final VoidCallback? onClearFilter;

  final bool filtered;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Icon(
                filtered ? Icons.search_off_rounded : Icons.event_available_rounded,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(filtered ? '没有符合条件的记录' : '还没有自定义重要日'),
              const SizedBox(height: 8),
              if (filtered)
                M3EButton(
                  style: M3EButtonStyle.text,
                  onPressed: onClearFilter,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt_off_outlined),
                      SizedBox(width: 8),
                      Text('清除筛选'),
                    ],
                  ),
                )
              else
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

class ImportantDaysPage extends StatefulWidget {
  const ImportantDaysPage({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMutate,
  });

  final AppController controller;
  final VoidCallback onAdd;
  final ValueChanged<EventOccurrence> onEdit;
  final ValueChanged<EventOccurrence> onDelete;
  final MutationRunner onMutate;

  @override
  State<ImportantDaysPage> createState() => _ImportantDaysPageState();
}

class _ImportantDaysPageState extends State<ImportantDaysPage> {
  final BatchSelection _selection = BatchSelection();
  final TextEditingController _searchController = TextEditingController();

  /// 搜索词与分类筛选只影响列表显示，不写库、不发通知，所以放在 State 里即可。
  String _term = '';
  String? _category;

  List<EventOccurrence> _visible = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onAdd = widget.onAdd;
    final today = CalendarEngine.dateOnly(DateTime.now());
    // 自带记录与内置条目一起搜：写「春节」要能搜到官方春节假期。
    // 控制器内部先按条件筛掉记录再算下一次发生，避免为被筛掉的记录白跑农历换算。
    final occurrences = controller.searchOccurrences(
      _term,
      category: _category,
      today: today,
    );
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
    _visible = [...upcoming, ...past];

            return RefreshIndicator(
              onRefresh: controller.refreshAll,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 120),
                    sliver: SliverList.list(
            children: [
              if (_selection.active)
                _SelectionBar(
                  count: _selection.countIn(_visible),
                  onCategory: _batchCategory,
                  onReminder: _batchReminder,
                  onDelete: _batchDelete,
                  onClose: () => setState(_selection.clear),
                ),
              Text(
                '重要日',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                '纪念日、生日、目标，以及接下来的假期与节日',
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
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _term = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索名称、备注或节日',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  isDense: true,
                  suffixIcon: _term.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _term = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              // 分类筛选：再点一次同一个分类即取消，_category 回到 null。
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in kEventCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (selected) => setState(
                            () => _category = selected ? category : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (occurrences.isEmpty) ...[
                _EmptyEvents(
                  onAdd: onAdd,
                  filtered: filtering,
                  onClearFilter: filtering ? _clearFilter : null,
                ),
              ] else ...[
                if (upcoming.isNotEmpty) ...[
                  _SectionHeading(
                    title: '接下来',
                    count: upcoming.length,
                  ),
                  const SizedBox(height: 10),
                  for (final (index, item) in upcoming.indexed)
                    _Entrance(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OccurrenceTile(
                          occurrence: item,
                          selectionMode: _selection.active,
                          selected: _selection.contains(item),
                          onEdit: () => _handleTap(item),
                          onLongPress: () =>
                              setState(() => _selection.select(item)),
                          onDelete: () => widget.onDelete(item),
                        ),
                      ),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SectionHeading(title: '已经走过', count: past.length),
                  const SizedBox(height: 10),
                  for (final (index, item) in past.indexed)
                    _Entrance(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OccurrenceTile(
                          occurrence: item,
                          selectionMode: _selection.active,
                          selected: _selection.contains(item),
                          onEdit: () => _handleTap(item),
                          onLongPress: () =>
                              setState(() => _selection.select(item)),
                          onDelete: () => widget.onDelete(item),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
        ),
      );
  }

  /// 是否正在按搜索词或分类筛选。用于区分「一条记录都没有」与
  /// 「有记录但被筛空了」两种空态。
  bool get filtering => _term.trim().isNotEmpty || _category != null;

  /// 一次清掉搜索词与分类筛选。
  void _clearFilter() {
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _term = '';
      _category = null;
    });
  }

  void _handleTap(EventOccurrence item) {
    if (_selection.active) {
      setState(() => _selection.toggle(item));
      return;
    }
    widget.onEdit(item);
  }

  Future<void> _batchCategory() async {
    final ids = _selection.eventIdsOf(_visible);
    if (ids.isEmpty) return;
    final category = await showCategoryPicker(context);
    if (category == null) return;
    await widget.onMutate(
      () => widget.controller.updateEventsCategory(ids, category),
      '已把 ${ids.length} 条改为「$category」',
    );
    _clearSelection();
  }

  Future<void> _batchReminder() async {
    final ids = _selection.eventIdsOf(_visible);
    if (ids.isEmpty) return;
    final days = await showReminderPicker(context);
    if (days == null) return;
    await widget.onMutate(
      () => widget.controller.updateEventsReminder(ids, days),
      '已更新 ${ids.length} 条的提醒',
    );
    _clearSelection();
  }

  Future<void> _batchDelete() async {
    final ids = _selection.eventIdsOf(_visible);
    final origins = _selection.originsOf(_visible);
    if (ids.isEmpty && origins.isEmpty) return;
    final confirmed =
        await confirmBulkDelete(context, ids.length + origins.length);
    if (confirmed != true) return;
    await widget.onMutate(
      () async {
        if (ids.isNotEmpty) await widget.controller.deleteEvents(ids);
        if (origins.isNotEmpty) await widget.controller.restoreOverrides(origins);
      },
      '已删除 ${ids.length} 条、恢复 ${origins.length} 条内置安排',
    );
    _clearSelection();
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(_selection.clear);
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
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onMutate,
  });

  final AppController controller;
  final MutationRunner onMutate;

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
              subtitle: const Text('默认关闭 · 时刻可逐条设置 · 不需要网络'),
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
          _undoCard(context),
          const SizedBox(height: 10),
          _themeCard(context),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded),
                  title: const Text('导出到文件'),
                  subtitle: const Text('记录、内置条目改动与外观设置，存成 JSON 文件'),
                  onTap: () => _exportBackupFile(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('从文件导入'),
                  subtitle: const Text('导入会替换本机的记录、改动与外观设置'),
                  onTap: () => _importBackupFile(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制备份到剪贴板'),
                  subtitle: const Text('临时转移用；剪贴板会被下一次复制冲掉'),
                  onTap: () => _copyBackup(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('从剪贴板导入'),
                  subtitle: const Text('配合上面的复制操作使用'),
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
                  Text('数据来源：${controller.holidaySource}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    controller.holidayFetchedAt == null
                        ? '内置安排随应用发布，联网后会自动获取最新版本'
                        : '更新于 ${_formatStamp(controller.holidayFetchedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${HolidayCatalog.sourceFor(HolidayCatalog.latestYear)}'
                    '（${HolidayCatalog.sourceDate}）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('其他年份只显示农历节日与节气；官方放假日期待正式公布后更新。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 14),
                  if (controller.holidayUpdating)
                    const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: M3ELoadingIndicator(size: 18),
                        ),
                        SizedBox(width: 10),
                        Text('正在获取最新安排…'),
                      ],
                    )
                  else
                    M3EButton(
                      style: M3EButtonStyle.tonal,
                      onPressed: () => onMutate(
                        controller.refreshHolidays,
                        '已更新 ${HolidayCatalog.latestYear} 年放假安排',
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_sync_outlined),
                          SizedBox(width: 8),
                          Text('检查更新'),
                        ],
                      ),
                    ),
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

  Widget _undoCard(BuildContext context) {
    final canUndo = controller.canUndo;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: const Icon(Icons.undo_rounded),
        title: const Text('撤销上一步改动'),
        subtitle: Text(
          canUndo ? '上一步：${controller.undoLabel}' : '暂时没有可撤销的改动',
        ),
        trailing: canUndo ? const Icon(Icons.chevron_right_rounded) : null,
        onTap: canUndo
            ? () => onMutate(controller.undo, '已撤销上一步改动')
            : null,
      ),
    );
  }

  Widget _themeCard(BuildContext context) {
    final settings = controller.settings;
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 12),
                Text('外观',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
              ],
            ),
            const SizedBox(height: 14),
            M3ESegmentedButton<AppThemeMode>(
              segments: const [
                M3ESegment(value: AppThemeMode.system, label: '跟随系统'),
                M3ESegment(value: AppThemeMode.light, label: '浅色'),
                M3ESegment(value: AppThemeMode.dark, label: '深色'),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => onMutate(
                () => controller.updateSettings(
                  settings.copyWith(themeMode: selection.first),
                ),
                '已切换外观',
              ),
            ),
            const SizedBox(height: 16),
            Text('配色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final seed in AppSeed.values)
                  Tooltip(
                    message: seed.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onMutate(
                        () => controller.updateSettings(
                          settings.copyWith(seed: seed),
                        ),
                        '已更换配色',
                      ),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(seed.colorValue),
                          border: Border.all(
                            color: seed == settings.seed
                                ? colors.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: seed == settings.seed
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.useDynamicColor,
              onChanged: (value) => onMutate(
                () => controller.updateSettings(
                  settings.copyWith(useDynamicColor: value),
                ),
                '已更新取色方式',
              ),
              title: const Text('跟随系统取色'),
              subtitle: const Text('Android 12 及以上使用壁纸配色'),
            ),
          ],
        ),
      ),
    );
  }

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
    await _confirmAndImport(context, source);
  }

  Future<void> _exportBackupFile(BuildContext context) async {
    try {
      final done = await controller.exportToFile();
      if (!context.mounted) return;
      // 系统分享面板在 Android 上判断不了内容最终去了哪，所以只说「已交给系统」，
      // 不承诺「已保存到某处」——那是在骗用户。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(done ? '备份已交给系统保存。' : '已取消导出。'),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      _showError('导出失败：$error');
    }
  }

  Future<void> _importBackupFile(BuildContext context) async {
    final String? source;
    try {
      source = await controller.importFromFile();
    } on Object catch (error) {
      if (!context.mounted) return;
      _showError('读取备份失败：$error');
      return;
    }
    // 用户在文件选择器上点了取消，不是错误，安静地什么都不做。
    if (source == null) return;
    if (!context.mounted) return;
    await _confirmAndImport(context, source);
  }

  /// 文件与剪贴板两条来源共用同一段「确认 → 导入 → 反馈」。
  Future<void> _confirmAndImport(BuildContext context, String source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('替换本机记录？'),
        content: const Text('导入会覆盖本机的记录、内置条目改动与外观设置。'),
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

/// 启动阶段的错误横幅：告知用户哪里没载入成功，并给一个重试入口。
class _StartupErrorBanner extends StatelessWidget {
  const _StartupErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '部分功能未能载入：$message',
                style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}


/// 时间戳：2026-02-15 09:30。
String _formatStamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// 所有「改动类」操作的统一入口：执行动作，成功后弹一条可撤销的提示。
typedef MutationRunner = Future<void> Function(
  Future<void> Function() action,
  String label,
);

/// 多选状态：长按条目进入多选，之后可批量改分类、提醒或删除。
class BatchSelection {
  final Set<String> keys = <String>{};

  bool get active => keys.isNotEmpty;

  /// 条目在多选里的稳定标识：自带记录用记录 id，内置条目用 origin。
  static String keyOf(EventOccurrence item) =>
      item.event != null ? 'event:${item.event!.id}' : 'origin:${item.origin}';

  bool contains(EventOccurrence item) => keys.contains(keyOf(item));

  void select(EventOccurrence item) => keys.add(keyOf(item));

  void toggle(EventOccurrence item) =>
      keys.contains(keyOf(item)) ? keys.remove(keyOf(item)) : keys.add(keyOf(item));

  void clear() => keys.clear();

  int countIn(Iterable<EventOccurrence> items) => items.where(contains).length;

  /// 选中的自带记录 id。
  List<String> eventIdsOf(Iterable<EventOccurrence> items) {
    final ids = <String>[];
    for (final item in items) {
      if (!contains(item)) continue;
      if (item.event case final event?) ids.add(event.id);
    }
    return ids;
  }

  /// 选中的内置条目标识。
  List<String> originsOf(Iterable<EventOccurrence> items) {
    final origins = <String>[];
    for (final item in items) {
      if (!contains(item)) continue;
      if (item.origin case final origin?) origins.add(origin);
    }
    return origins;
  }
}

/// 多选模式下的批量操作条。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCategory,
    required this.onReminder,
    required this.onDelete,
    required this.onClose,
  });

  final int count;
  final VoidCallback onCategory;
  final VoidCallback onReminder;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Icon(Icons.checklist_rounded, color: colors.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '已选 $count 项',
                style: TextStyle(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '统一改分类',
              onPressed: onCategory,
              icon: const Icon(Icons.sell_outlined),
            ),
            IconButton(
              tooltip: '统一改提醒',
              onPressed: onReminder,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            IconButton(
              tooltip: '删除选中',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            IconButton(
              tooltip: '退出多选',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一改分类。
Future<String?> showCategoryPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('统一改成', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in kEventCategories)
                    ActionChip(
                      label: Text(category),
                      onPressed: () => Navigator.pop(context, category),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

/// 统一改提醒。
///
/// 改成有状态的弹层，是为了容纳「自定义天数」——一个纯函数弹层没法在
/// 用户点开自定义时临时多出一个数字输入框。
Future<int?> showReminderPicker(BuildContext context) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _ReminderPickerSheet(),
    );

class _ReminderPickerSheet extends StatefulWidget {
  const _ReminderPickerSheet();

  @override
  State<_ReminderPickerSheet> createState() => _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends State<_ReminderPickerSheet> {
  final TextEditingController _custom = TextEditingController();
  bool _askingCustom = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统一设置提醒',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            // 批量只改提前量，不改时刻：各条记录自己的提醒时刻保持不变。
            Text('只调整提前几天，各条记录原本的提醒时刻不变',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('关闭提醒'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, -1),
            ),
            for (final option in kReminderLeadOptions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(option.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, option.days),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('自定义天数'),
              trailing: Icon(
                _askingCustom
                    ? Icons.expand_less_rounded
                    : Icons.chevron_right_rounded,
              ),
              onTap: () => setState(() => _askingCustom = !_askingCustom),
            ),
            if (_askingCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _custom,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  labelText: '提前多少天提醒',
                  helperText: '0 到 365 之间',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              M3EButton(
                style: M3EButtonStyle.filled,
                onPressed: _submit,
                child: const Text('应用'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _submit() {
    final days = int.tryParse(_custom.text.trim());
    if (days == null || days < 0 || days > 365) return;
    Navigator.pop(context, days);
  }
}

/// 批量删除确认。
Future<bool> confirmBulkDelete(BuildContext context, int count) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除选中的条目？'),
        content: Text('共 $count 项；内置条目会恢复成公布的安排。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

/// 切换底部导航时的淡入淡出，页面状态仍由 IndexedStack 保留。
class _TabTransition extends StatefulWidget {
  const _TabTransition({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: M3EMotion.medium2,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _controller.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// 列表逐项入场：按序号错开，整屏看起来是一段连贯的动效。
class _Entrance extends StatefulWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  /// 序号过大时不再等待，避免末尾出现明显延迟。
  static const int maxDelayIndex = 12;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: M3EMotion.long2,
    value: widget.index > maxDelayIndex ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.index > maxDelayIndex) return;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 60) +
          Duration(milliseconds: 45 * widget.index), () {
        if (mounted) _controller.forward();
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// 年度倒计时：今年走到第几天、还剩多少天。
class _YearCountdownCard extends StatelessWidget {
  const _YearCountdownCard({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final progress = YearProgress.of(now);
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.progress),
      duration: M3EMotion.extraLong1,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${progress.year} 年',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  )),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('${progress.daysLeft}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: colors.primary,
                                        height: 1,
                                      )),
                              const SizedBox(width: 6),
                              Text('天后跨年',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      )),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18),
                        const SizedBox(height: 6),
                        Text(
                          '第 ${progress.dayOfYear}/${progress.totalDays} 天',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress.daysLeft == 0 ? '今天就是今年最后一天' : '珍惜剩下的每一天',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 按下时轻微缩放，给卡片一点物理反馈；不影响水波纹。
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  /// 按下时缩到的比例。
  static const double pressedScale = 0.97;

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? _Pressable.pressedScale : 1,
      duration: M3EMotion.short2,
      curve: Curves.easeOut,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: widget.child,
      ),
    );
  }
}

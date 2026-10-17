import 'package:lunar/lunar.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/calendar_engine.dart';
import '../models/countdown_event.dart';
import 'cover_field.dart';
import 'event_editor.dart' show formatHour;

/// 一条重要日的详情页：倒数、里程碑、历次发生的时间线，以及编辑与删除入口。
///
/// 自带记录与内置条目共用这一个页面，但两者能做的事不同：内置条目（官方假期、
/// 传统节日）没有「最初那一天」，也就没有时间线与周年，页面据此自动隐藏那几块。
///
/// 页面自己订阅 [controller]：详情页是 push 出来的独立路由，不在 `main.dart` 那层
/// `AnimatedBuilder` 之下，不订阅的话「编辑」保存完还停在旧标题、旧日期上。
class EventDetailPage extends StatefulWidget {
  const EventDetailPage({
    super.key,
    required this.item,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  /// 从列表里点进来的那一条。日期即「接下来那一次」。
  final EventOccurrence item;

  final AppController controller;

  /// 详情页里点「编辑」时回调，弹编辑器或改动面板。
  final Future<void> Function(EventOccurrence) onEdit;

  /// 删除；内置条目则是恢复默认。完成后详情页自己退栈。
  final Future<void> Function(EventOccurrence) onDelete;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  /// 当前展示的那一条。控制器每次落库后都会换成按最新数据重算的结果。
  late EventOccurrence _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  /// 落库之后把这一条换成最新的：改完标题、日期、重复方式立刻反映在页面上。
  ///
  /// 重算不出来时保持原样，不在这里退栈 —— 删除与恢复默认本来就有自己的退栈路径，
  /// 这里再退一次会把下面那一页也一起弹掉。
  void _sync() {
    if (!mounted) return;
    final fresh = _latest();
    if (fresh == null) return;
    setState(() => _item = fresh);
  }

  /// 按控制器现在的数据重算这一条；记录已被删掉、内置条目已被隐藏时返回 null。
  ///
  /// 两条路径都走现成的算法：自带记录用 [CalendarEngine.nextOccurrence]，内置条目用
  /// [AppController.builtInOccurrences]。在页面里再写一遍「哪一天、还剩几天」，
  /// 迟早会和列表页算出两个数。
  EventOccurrence? _latest() {
    final event = _item.event;
    if (event != null) {
      for (final candidate in widget.controller.events) {
        if (candidate.id == event.id) {
          return CalendarEngine.nextOccurrence(candidate, DateTime.now());
        }
      }
      return null;
    }
    final origin = _item.origin;
    if (origin == null) return null;
    final builtIn = widget.controller.builtInOccurrences(DateTime.now());
    for (final candidate in builtIn) {
      if (candidate.origin == origin) return candidate;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final today = CalendarEngine.dateOnly(DateTime.now());
    final event = item.event;
    final recurrenceLabel = recurrenceText(event?.recurrence);
    final moments = CalendarEngine.historyMoments(event, item.date);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: () => widget.onEdit(item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: item.origin == null ? '删除' : '恢复默认',
            onPressed: () async {
              await widget.onDelete(item);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // 有封面就摆在最上面：它是这条记录最直观的那一眼。
          if (item.coverPath case final String cover)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: CoverImage(
                store: widget.controller.coverStore,
                filename: cover,
              ),
            ),
          _CountdownCard(item: item),
          const SizedBox(height: 16),
          _FactsCard(item: item, recurrenceLabel: recurrenceLabel),
          if (item.note.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _NoteCard(note: item.note.trim()),
          ],
          const SizedBox(height: 16),
          _TimelineCard(
            moments: moments,
            today: today,
            // 内置条目只有一次发生，画时间线只是把同一行换个样式。
            hasHistory: event != null,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => widget.onEdit(item),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_outlined),
                const SizedBox(width: 8),
                Text(
                  item.origin == null ? '编辑这条记录' : '改动这条内置条目',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「一次 / 公历每年 / 农历每年」；内置条目没有重复方式，返回空串。
String recurrenceText(EventRecurrence? recurrence) => switch (recurrence) {
      null => '',
      EventRecurrence.once => '只发生一次',
      EventRecurrence.solarYearly => '公历每年',
      EventRecurrence.lunarYearly => '农历每年',
    };

/// 顶部大卡片：倒数天数 + 一句摘要。
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.item});

  final EventOccurrence item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final remaining = item.daysRemaining;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, colors.tertiary, .45)!,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                remaining == 0
                    ? '今天'
                    : remaining.abs().toString(),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -2,
                    ),
              ),
              if (remaining != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    remaining > 0 ? '天后' : '天前',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
            ],
          ),
          // 算不出里程碑时整行不出现，而不是编一个数字。文案与首页大卡片、
          // 列表条目同源，三处不会各说各话。
          if (CalendarEngine.milestoneTextOf(item) case final text?) ...[
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// 基本信息：日期、农历、重复方式、分类、提醒。
class _FactsCard extends StatelessWidget {
  const _FactsCard({
    required this.item,
    required this.recurrenceLabel,
  });

  final EventOccurrence item;
  final String recurrenceLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = item.date;
    final lunar = Lunar.fromDate(date);
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          children: [
            _Fact(
              icon: Icons.calendar_month_rounded,
              label: '日期',
              value: '${date.year}年${date.month}月${date.day}日'
                  '${date.weekday == DateTime.sunday || date.weekday == DateTime.saturday ? ' 周末' : ''}',
            ),
            _Fact(
              icon: Icons.local_florist_outlined,
              label: '农历',
              value: '农历${lunar.getMonthInChinese()}${lunar.getDayInChinese()}',
            ),
            if (recurrenceLabel.isNotEmpty)
              _Fact(
                icon: Icons.event_repeat_outlined,
                label: '重复',
                value: recurrenceLabel,
              ),
            _Fact(
              icon: Icons.sell_outlined,
              label: '分类',
              value: item.subtitle,
            ),
            _Fact(
              icon: Icons.notifications_outlined,
              label: '提醒',
              value: _reminderText(),
            ),
          ],
        ),
      ),
    );
  }

  /// 「不提醒」或「提前 7 天 · 09:00」。
  ///
  /// 时刻也要写出来：编辑器里让用户选过 0–23 点，这里只说「提前几天」的话，
  /// 用户没法在这一页确认自己设的几点会响。
  String _reminderText() {
    final days = item.reminderDays;
    if (days < 0) return '不提醒';
    final lead = switch (days) {
      0 => '当天提醒',
      1 => '提前 1 天',
      7 => '提前 7 天',
      _ => '提前 $days 天',
    };
    return '$lead · ${formatHour(item.reminderHour)}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            SizedBox(
              width: 42,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
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
            Text('备注', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Text(note, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// 历次发生的时间线：每一次发生各一行，标注已过天数与第几次。
///
/// [hasHistory] 为 false 表示这是内置条目 —— 它只有一次发生，没有「上一次」
/// 可依，这时给一句说明而不是空白的列表。
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.moments,
    required this.today,
    required this.hasHistory,
  });

  final List<OccurrenceMoment> moments;
  final DateTime today;
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('时间线', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (!hasHistory)
              Text('官方假期与节日只有这一次发生，没有别的日子可看。', style: hint)
            else if (moments.isEmpty)
              // 农历月日被写坏（例如月份越界）时一条都算不出来。说清楚，
              // 而不是摆一个只有标题的空卡片。
              Text('这条记录的农历日期算不出来，列不出历次发生。', style: hint)
            else
              for (final moment in moments)
                _TimelineRow(moment: moment, today: today),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.moment, required this.today});

  final OccurrenceMoment moment;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final past = moment.isPast(today);
    final date = moment.date;
    final milestone = moment.milestone;
    // 已过天数与「第几次」分开取，不用 milestoneSummary：那份摘要里带着周年，
    // 右边再摆一个「第 N 次」就等于把同一句话说两遍（年度重复里两者恒等）。
    // 算不出来时两项都是空串，界面据此不编数字。
    final elapsed = milestone == null
        ? ''
        : CalendarEngine.milestoneElapsedLabel(milestone);
    final cycle =
        milestone == null ? '' : CalendarEngine.milestoneCycleLabel(milestone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: past ? colors.primary : colors.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.year}年${date.month}月${date.day}日',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: past ? null : colors.onSurfaceVariant,
                      ),
                ),
                if (elapsed.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    elapsed,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (cycle.isNotEmpty)
            Text(
              cycle,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

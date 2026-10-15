import 'package:flutter/material.dart';

import '../logic/schedule_editor.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../state/schedule_controller.dart';
import 'ui_helpers.dart';

// ============================================================================
// 阶段 4 的主角：调休 / 临时调整。
//
// 现实里课表不是「第 3 到 15 周每周都上」这么理想：
//   · 国庆放假那周 —— 按规律该上的课其实不上；
//   · 放假调休补课 —— 本来不在这周的课要挪过来上一天。
//
// 这个页面就是给这两种情况用的：选一个周次，逐门课告诉 App
// 「这周照常 / 这周一定上 / 这周不上」。改动即时保存，不用点保存键。
// ============================================================================

/// 一门课在某一周的三种状态。
enum _Choice {
  /// 不做任何调整，按课程自己的周次规律算。
  follow,

  /// 强制这周上（补课）。
  forceOn,

  /// 强制这周不上（停课）。
  forceOff,
}

/// 整周批量按钮的统一样式：收紧内边距、字号略小，
/// 保证「全部照常 / 全部停课」在窄屏上也各占一行。
final ButtonStyle _batchButtonStyle = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  textStyle: const TextStyle(fontSize: 13.5),
);

class OverridesPage extends StatefulWidget {
  const OverridesPage({super.key, required this.controller, this.now});

  final ScheduleController controller;

  /// 「今天」是哪一天；写测试时传固定日期，结果才可复现。
  final DateTime? now;

  @override
  State<OverridesPage> createState() => _OverridesPageState();
}

class _OverridesPageState extends State<OverridesPage> {
  late DateTime _now;
  late int _week;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _week = _defaultWeek();
  }

  /// 打开页面时默认停在第几周：优先「今天」，不能识别就第 1 周。
  int _defaultWeek() {
    final data = widget.controller.data;
    if (data == null) return 1;
    final today = data.semester.weekOf(_now);
    if (data.semester.containsWeek(today)) return today;
    return 1;
  }

  int get _totalWeeks =>
      widget.controller.data?.semester.totalWeeks ?? 20;

  void _goToWeek(int week) {
    if (week < 1 || week > _totalWeeks || week == _week) return;
    setState(() => _week = week);
  }

  void _goToToday() {
    final data = widget.controller.data;
    if (data == null) return;
    final today = data.semester.weekOf(_now);
    if (data.semester.containsWeek(today)) {
      _goToWeek(today);
    } else {
      _goToWeek(1);
    }
  }

  /// 这一周需要显示的课程。
  ///
  /// 包含两类：按规律要上的，以及**被手动调整过**的——
  /// 后者即使现在不上也得显示出来，否则你没法把它改回去。
  List<Course> _coursesOfWeek() {
    final data = widget.controller.data;
    if (data == null) return const <Course>[];
    final result = data.courses
        .where((c) => c.isActiveInWeek(_week) || c.overrides.containsKey(_week))
        .toList();
    result.sort(compareCourses);
    return result;
  }

  Future<void> _setOverride(Course course, _Choice choice) async {
    switch (choice) {
      case _Choice.follow:
        await widget.controller.setOverride(course.id, _week, null);
        break;
      case _Choice.forceOn:
        await widget.controller.setOverride(course.id, _week, true);
        break;
      case _Choice.forceOff:
        await widget.controller.setOverride(course.id, _week, false);
        break;
    }
  }

  /// 整周批量：把这一周所有课都设成同一种状态。
  Future<void> _setAll(bool value) async {
    final courses = _coursesOfWeek();
    if (courses.isEmpty) {
      _toast('这一周本来就没有课');
      return;
    }
    await widget.controller.setOverridesForCourses(
      courses.map((c) => c.id),
      _week,
      value,
    );
    if (!mounted) return;
    _toast(value ? '第 $_week 周已设为全部照常上课' : '第 $_week 周已设为全部停课');
  }

  Future<void> _clearAll() async {
    final data = widget.controller.data;
    if (data == null) return;
    final count = countOverrides(data.courses);
    if (count == 0) {
      _toast('还没有任何调休设置');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部调休？'),
        content: Text('一共 $count 条调休设置会被删掉，所有课都回到按周次规律排课。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await widget.controller.clearOverrides();
    if (!mounted) return;
    _toast('已清空全部调休设置');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 调休是「点一下立刻生效」的，所以这一页必须盯着控制器：
    // 数据一变就整页重画，按钮的选中状态、课程数量、右上角「清空」按钮
    // 才会跟着变。少了这一层，点完之后界面会停在旧样子上。
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = widget.controller.data;

    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final courses = _coursesOfWeek();
    final overrideCount = countOverrides(data.courses);

    return Scaffold(
      appBar: AppBar(
        title: const Text('调休 / 临时调整'),
        actions: <Widget>[
          if (overrideCount > 0)
            TextButton(
              onPressed: _clearAll,
              child: const Text('清空'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          _WeekSelector(
            week: _week,
            totalWeeks: _totalWeeks,
            semester: data.semester,
            now: _now,
            onPrev: () => _goToWeek(_week - 1),
            onNext: () => _goToWeek(_week + 1),
            onToday: _goToToday,
            onPick: _goToWeek,
          ),
          const SizedBox(height: 14),

          // 整周批量操作：放假那种「一整周都不上课」一次点完。
          // 文案刻意压到 4 个字，并且收紧内边距 —— 否则在窄屏上
          // 「全部停课」会被挤成两行，和左边的按钮一高一低很难看。
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  style: _batchButtonStyle,
                  onPressed: () => _setAll(true),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('全部照常'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: _batchButtonStyle,
                  onPressed: () => _setAll(false),
                  icon: const Icon(Icons.beach_access_outlined, size: 18),
                  label: const Text('全部停课'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Text(
            '第 $_week 周的课程（${courses.length} 节）',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          if (courses.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.event_busy_outlined,
                    size: 36,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '第 $_week 周本来就没有课',
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '换一个周次看看，或者去课表里先添加课程。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            for (final course in courses)
              _OverrideCard(
                course: course,
                week: _week,
                onChanged: (choice) => _setOverride(course, choice),
              ),

          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '「按规律」= 这门课自己的周次说了算，你什么都没改。\n'
              '「这周一定上」= 补课，本来不在这周的课也要上。\n'
              '「这周不上」= 停课，比如国庆放假。\n\n'
              '改动会立刻保存，不需要点保存键。整份课表现在共有 '
              '$overrideCount 条调休设置。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- 周次选择

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.week,
    required this.totalWeeks,
    required this.semester,
    required this.now,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPick,
  });

  final int week;
  final int totalWeeks;
  final Semester semester;
  final DateTime now;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = semester.weekOf(now) == week;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一周',
            onPressed: week > 1 ? onPrev : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showWeekPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '第 $week 周',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Semester.parityLabel(week),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Semester.formatDate(semester.mondayOfWeek(week))} 起'
                      '${isToday ? ' · 就是本周' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isToday)
            IconButton(
              tooltip: '回到本周',
              onPressed: onToday,
              icon: const Icon(Icons.today_outlined),
            ),
          IconButton(
            tooltip: '下一周',
            onPressed: week < totalWeeks ? onNext : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeekPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 380,
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('跳到第几周', style: TextStyle(fontSize: 15)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: totalWeeks,
                  itemBuilder: (itemContext, index) {
                    final w = index + 1;
                    return ListTile(
                      dense: true,
                      selected: w == week,
                      leading: Text('$w'),
                      title: Text('第 $w 周 · ${Semester.parityLabel(w)}'),
                      subtitle: Text(
                        Semester.formatDate(semester.mondayOfWeek(w)),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(w),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }
}

// ---------------------------------------------------------------------- 课程卡片

class _OverrideCard extends StatelessWidget {
  const _OverrideCard({
    required this.course,
    required this.week,
    required this.onChanged,
  });

  final Course course;
  final int week;
  final ValueChanged<_Choice> onChanged;

  _Choice get _current {
    final override = course.overrides[week];
    if (override == null) return _Choice.follow;
    return override ? _Choice.forceOn : _Choice.forceOff;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final choice = _current;
    final active = course.isActiveInWeek(week);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: choice == _Choice.follow
              ? scheme.outlineVariant
              : (active ? scheme.primary : scheme.error),
          width: choice == _Choice.follow ? 1 : 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  course.courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 这门课这一周到底上不上，用一个小图标立刻说清楚。
              // （刻意不用文字标签 —— 会和下面的按钮文案撞车，看起来也啰嗦。）
              Icon(
                active ? Icons.check_circle : Icons.do_not_disturb_on_outlined,
                size: 20,
                color: active ? scheme.primary : scheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${weekdayFull(course.dayOfWeek)} · 第 ${course.node} 节'
            ' · ${course.ruleText}'
            '${course.classroom.isEmpty ? '' : ' · ${course.classroom}'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SegmentedButton<_Choice>(
            segments: const <ButtonSegment<_Choice>>[
              ButtonSegment<_Choice>(
                value: _Choice.follow,
                label: Text('按规律'),
              ),
              ButtonSegment<_Choice>(
                value: _Choice.forceOn,
                label: Text('这周上'),
              ),
              ButtonSegment<_Choice>(
                value: _Choice.forceOff,
                label: Text('这周不上'),
              ),
            ],
            selected: <_Choice>{choice},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll<TextStyle>(
                TextStyle(fontSize: 12.5),
              ),
            ),
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (next != choice) onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}

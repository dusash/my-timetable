import 'package:flutter/material.dart';

import '../data/schedule_data.dart';
import '../logic/grid_builder.dart';
import '../logic/schedule_editor.dart';
import '../logic/week_calculator.dart';
import '../models/course.dart';
import '../models/semester.dart';
import 'course_card.dart';
import 'course_edit_page.dart';
import 'course_palette.dart';
import 'ui_helpers.dart';

/// 网格里「一节大课」占的高度。
const double kSlotHeight = 62;

/// 左侧「第几节 / 时间」那一列的宽度。
const double kTimeColumnWidth = 46;

/// 今日所在列的淡色底（ARGB 里的前两位是透明度，0x14 约等于 8%）。
const Color kTodayTint = Color(0x143F6FB5);

/// 阶段 2 的主角：一周课表网格。
///
/// 它自己不判断「哪周上什么课」——那是 [WeekCalculator] 的活。
/// 这里只负责把算出来的结果摆成 7 列 × 若干行的格子。
///
/// 阶段 3 起它多了一个「只读 / 可编辑」的分身：
///   · 不传 [onDataChanged] → 纯展示（写测试、以后做「查看同学课表」时用）；
///   · 传了 [onDataChanged] → 出现「+ 添加课程」「点空格新增」「编辑 / 删除」。
/// 这样界面本身不需要知道数据存在哪儿，也不需要认识任何数据库。
class WeekGridPage extends StatefulWidget {
  const WeekGridPage({
    super.key,
    required this.data,
    this.now,
    this.onDataChanged,
    this.onLoadSample,
    this.onOpenSettings,
    this.onOpenShare,
    this.onOpenImport,
  });

  final ScheduleData data;

  /// 「今天」是哪一天。平时不用传（用系统时间），
  /// 写测试时可以传一个固定日期，结果才可复现。
  final DateTime? now;

  /// 课表被改动后回调出去（传的是改完的整份数据），由上层负责保存。
  final ValueChanged<ScheduleData>? onDataChanged;

  /// 点右上角齿轮时调用。
  final VoidCallback? onOpenSettings;

  /// 点右上角分享图标时调用。
  final VoidCallback? onOpenShare;

  /// 点空课表页的「先看看示例课表」时调用。
  final VoidCallback? onLoadSample;

  /// 点空课表页的「从教务系统导入」时调用。
  final VoidCallback? onOpenImport;

  @override
  State<WeekGridPage> createState() => _WeekGridPageState();
}

class _WeekGridPageState extends State<WeekGridPage> {
  /// 当前查看第几周。
  late int _week;

  /// 真实今天属于第几周（0 表示还没开学）。
  late int _todayWeek;

  /// 判定「今天」用的时间点。
  late final DateTime _now = widget.now ?? DateTime.now();

  /// 是否显示周六周日（默认只显示周一到周五，手机屏幕窄，看得更清楚）。
  bool _showWeekend = false;

  @override
  void initState() {
    super.initState();
    _syncWeek();
  }

  @override
  void didUpdateWidget(WeekGridPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 学期设置可能被改过（比如总周数从 20 改成 16），把当前周次夹回合法范围。
    if (oldWidget.data.semester.totalWeeks != widget.data.semester.totalWeeks ||
        oldWidget.data.semester.week1Start != widget.data.semester.week1Start) {
      _syncWeek();
    }
  }

  /// 根据「今天」算出该看第几周，并保证不越界。
  void _syncWeek() {
    final total = widget.data.semester.totalWeeks;
    _todayWeek = widget.data.semester.weekOf(_now);
    final wanted = _todayWeek < 1 ? 1 : (_todayWeek > total ? total : _todayWeek);
    _week = wanted;
  }

  /// 是否可以编辑（上层有没有给保存的出口）。
  bool get _editable => widget.onDataChanged != null;

  bool get _isCurrentWeek => _week == _todayWeek;

  void _goToWeek(int week) {
    final total = widget.data.semester.totalWeeks;
    if (week < 1 || week > total || week == _week) return;
    setState(() => _week = week);
  }

  void _backToCurrentWeek() {
    if (_todayWeek < 1) {
      _goToWeek(1);
    } else if (_todayWeek > widget.data.semester.totalWeeks) {
      _goToWeek(widget.data.semester.totalWeeks);
    } else {
      _goToWeek(_todayWeek);
    }
  }

  // ------------------------------------------------------------ 阶段 3：增删改

  /// 编辑表单里「第几节」下拉要开到多少。
  ///
  /// 取「作息表节数」和「现有课程节次」的较大值，再兜底到 8 节——
  /// 这样一份全新的空课表也能直接录到第 8 节。
  int _nodeLimitOf(ScheduleData data) {
    var limit = 8;
    for (final p in data.periods) {
      if (p.node > limit) limit = p.node;
    }
    for (final c in data.courses) {
      if (c.node > limit) limit = c.node;
    }
    return limit;
  }

  /// 打开编辑表单。返回 true 表示用户确实保存了。
  Future<bool> _openEditor(ScheduleData data, {Course? initial, int? day, int? node}) async {
    final result = await Navigator.of(context).push<Course>(
      MaterialPageRoute<Course>(
        builder: (_) => CourseEditPage(
          semester: data.semester,
          maxNode: _nodeLimitOf(data),
          initial: initial,
          existingCourses: data.courses,
          initialDayOfWeek: day,
          initialNode: node,
        ),
      ),
    );
    if (result == null || !mounted) return false;

    // 用最新的数据来拼，避免表单开着的时候课表被别处改过。
    final latest = widget.data;
    widget.onDataChanged!(
      latest.copyWith(courses: upsertCourseInList(latest.courses, result)),
    );
    return true;
  }

  /// 新增一门课（可以从空白格子点进来，自动带上星期和节次）。
  Future<void> _addCourse({int? day, int? node}) {
    return _openEditor(widget.data, day: day, node: node).then((_) {});
  }

  /// 修改一门课。
  Future<void> _editCourse(Course course) {
    return _openEditor(widget.data, initial: course).then((_) {});
  }

  /// 删除一门课（先问一句，删完还能撤销）。
  Future<void> _deleteCourse(Course course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除「${course.courseName}」？'),
        content: const Text('只会删掉这一条安排，其他课程不受影响。'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final latest = widget.data;
    widget.onDataChanged!(
      latest.copyWith(courses: removeCourseFromList(latest.courses, course.id)),
    );

    // 给一次后悔的机会：手滑删错了能立刻撤回。
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${course.courseName}」'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              if (!mounted) return;
              final current = widget.data;
              widget.onDataChanged!(
                current.copyWith(
                  courses: upsertCourseInList(current.courses, course),
                ),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final calculator = data.calculator;
    final days = _showWeekend
        ? const <int>[1, 2, 3, 4, 5, 6, 7]
        : const <int>[1, 2, 3, 4, 5];
    final minNode = calculator.minNode;
    final maxNode = calculator.maxNode;
    final nodeCount = maxNode - minNode + 1;
    // 整份课表统一分配一次颜色，保证每门课颜色固定且不重样。
    final palettes = buildCoursePaletteMap(data.courses);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: <Widget>[
          IconButton(
            tooltip: _showWeekend ? '只看周一到周五' : '连周末一起看',
            onPressed: () => setState(() => _showWeekend = !_showWeekend),
            icon: Icon(
              _showWeekend ? Icons.filter_5_outlined : Icons.filter_7_outlined,
            ),
          ),
          if (widget.onOpenShare != null)
            IconButton(
              tooltip: '分享 / 导入课表',
              onPressed: widget.onOpenShare,
              icon: const Icon(Icons.qr_code_2_outlined),
            ),
          if (widget.onOpenSettings != null)
            IconButton(
              tooltip: '设置',
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: () => _addCourse(),
              icon: const Icon(Icons.add),
              label: const Text('添加课程'),
            )
          : null,
      body: data.courses.isEmpty ? _buildEmptyState(context) : _buildGrid(data, calculator, days, minNode, maxNode, nodeCount, palettes),
    );
  }

  /// 一门课都没有时的引导页（新用户第一眼看到的就是它）。
  ///
  /// 给三条路，覆盖三种不同的人：
  ///   1. 想自己录 → 「添加第一门课」（也可以直接点课表里的空格子）；
  ///   2. 教务系统里已经有课表 → 「从教务系统导入」，复制粘贴就完事；
  ///   3. 还没决定要不要用 → 「先看看示例课表」，先看看它长什么样。
  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.event_available_outlined,
              size: 64,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有课程',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _editable
                  ? '自己录一门，或者把教务系统的课表\n复制过来一键导入。'
                  : '这份课表是空的。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            if (_editable) ...<Widget>[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => _addCourse(),
                icon: const Icon(Icons.add),
                label: const Text('添加第一门课'),
              ),
              if (widget.onOpenImport != null) ...<Widget>[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenImport,
                  icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                  label: const Text('从教务系统导入'),
                ),
              ],
            ],
            if (widget.onLoadSample != null) ...<Widget>[
              const SizedBox(height: 16),
              TextButton(
                onPressed: widget.onLoadSample,
                child: const Text('先看看示例课表'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 正常情况下的课表网格。
  Widget _buildGrid(
    ScheduleData data,
    WeekCalculator calculator,
    List<int> days,
    int minNode,
    int maxNode,
    int nodeCount,
    Map<String, CoursePalette> palettes,
  ) {
    return Column(
      children: <Widget>[
        _WeekBar(
          semester: data.semester,
          week: _week,
          isCurrentWeek: _isCurrentWeek,
          onPrev: () => _goToWeek(_week - 1),
          onNext: () => _goToWeek(_week + 1),
          onBackToToday: _backToCurrentWeek,
        ),
        _DayHeaderRow(
          semester: data.semester,
          week: _week,
          days: days,
          todayWeek: _todayWeek,
          now: _now,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 左右滑动切换周次：向左滑看下一周，向右滑看上一周。
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) {
                _goToWeek(_week + 1);
              } else if (velocity > 200) {
                _goToWeek(_week - 1);
              }
            },
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _TimeColumn(
                    calculator: calculator,
                    minNode: minNode,
                    maxNode: maxNode,
                  ),
                  for (final day in days)
                    Expanded(
                      child: _DayColumn(
                        data: data,
                        palettes: palettes,
                        week: _week,
                        day: day,
                        minNode: minNode,
                        maxNode: maxNode,
                        nodeCount: nodeCount,
                        isToday: _week == _todayWeek && day == _now.weekday,
                        onTapSlot: _editable
                            ? (d, n) => _addCourse(day: d, node: n)
                            : null,
                        onEdit: _editable ? _editCourse : null,
                        onDelete: _editable ? _deleteCourse : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------- 顶部栏

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.semester,
    required this.week,
    required this.isCurrentWeek,
    required this.onPrev,
    required this.onNext,
    required this.onBackToToday,
  });

  final Semester semester;
  final int week;
  final bool isCurrentWeek;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onBackToToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monday = semester.mondayOfWeek(week);
    final sunday = monday.add(const Duration(days: 6));

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: week > 1 ? onPrev : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  '第 $week 周 · ${Semester.parityLabel(week)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${slashDate(monday)} - ${slashDate(sunday)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: week < semester.totalWeeks ? onNext : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
          ),
          if (!isCurrentWeek)
            IconButton(
              onPressed: onBackToToday,
              icon: const Icon(Icons.today_outlined),
              tooltip: '回到本周',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- 星期表头

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.semester,
    required this.week,
    required this.days,
    required this.todayWeek,
    required this.now,
  });

  final Semester semester;
  final int week;
  final List<int> days;
  final int todayWeek;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: kTimeColumnWidth,
            height: 46,
            child: Center(
              child: Text(
                '节次',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final day in days)
            Expanded(
              child: _DayHeaderCell(
                day: day,
                date: semester.dateOf(week, day),
                isToday: week == todayWeek && day == now.weekday,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.date,
    required this.isToday,
  });

  final int day;
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      decoration: BoxDecoration(
        color: isToday ? scheme.primary : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                weekdayFull(day),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isToday ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
              Text(
                slashDate(date),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: isToday
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 左侧节次列

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.calculator,
    required this.minNode,
    required this.maxNode,
  });

  final WeekCalculator calculator;
  final int minNode;
  final int maxNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: kTimeColumnWidth,
      child: Column(
        children: <Widget>[
          for (var node = minNode; node <= maxNode; node++)
            Container(
              height: kSlotHeight,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
                ),
              ),
              // 用 FittedBox 包住三行文字：
              // 手机系统把字体调大时，内容会自动等比缩小，
              // 永远不会撑破 62 像素高的格子（不会再报 overflow）。
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$node',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        calculator.periodOf(node)?.start ?? '',
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        calculator.periodOf(node)?.end ?? '',
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: scheme.onSurfaceVariant,
                        ),
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
}

// ---------------------------------------------------------------- 每天一列

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.data,
    required this.palettes,
    required this.week,
    required this.day,
    required this.minNode,
    required this.maxNode,
    required this.nodeCount,
    required this.isToday,
    this.onTapSlot,
    this.onEdit,
    this.onDelete,
  });

  final ScheduleData data;
  final Map<String, CoursePalette> palettes;
  final int week;
  final int day;
  final int minNode;
  final int maxNode;
  final int nodeCount;
  final bool isToday;

  /// 点空白格子时调用（参数是 星期、节次）；为 null 表示不可编辑。
  final void Function(int day, int node)? onTapSlot;

  /// 课程详情弹窗里的「编辑」；为 null 就不显示这个按钮。
  final void Function(Course course)? onEdit;

  /// 课程详情弹窗里的「删除」；为 null 就不显示这个按钮。
  final void Function(Course course)? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocks = buildDayBlocks(
      data.calculator,
      week: week,
      day: day,
      minNode: minNode,
      maxNode: maxNode,
    );

    return SizedBox(
      height: nodeCount * kSlotHeight,
      child: Stack(
        children: <Widget>[
          if (isToday) Positioned.fill(child: ColoredBox(color: kTodayTint)),
          // 每个格子画一条底线，形成网格；同时也是「点空白处新增课程」的落点。
          Column(
            children: <Widget>[
              for (var i = 0; i < nodeCount; i++)
                GestureDetector(
                  // opaque：让这个空容器也能接住点击（默认空装饰是接不住的）。
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapSlot == null
                      ? null
                      : () => onTapSlot!(day, minNode + i),
                  child: Container(
                    height: kSlotHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // 课程卡片。画在网格线上面，所以点卡片永远是点卡片，不会误触「新增」。
          for (final block in blocks)
            Positioned(
              top: (block.startNode - minNode) * kSlotHeight + 2,
              left: 2,
              right: 2,
              height: block.span * kSlotHeight - 4,
              child: CourseBlockCard(
                course: block.course,
                palette: paletteOf(palettes, block.course.courseName),
                isGhost: block.isGhost,
                span: block.span,
                onTap: () => showCourseDetail(
                  context,
                  data: data,
                  course: block.course,
                  palette: paletteOf(palettes, block.course.courseName),
                  week: week,
                  onEdit: onEdit == null ? null : () => onEdit!(block.course),
                  onDelete: onDelete == null
                      ? null
                      : () => onDelete!(block.course),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

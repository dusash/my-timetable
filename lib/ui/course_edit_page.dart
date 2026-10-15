import 'package:flutter/material.dart';

import '../logic/schedule_editor.dart';
import '../models/course.dart';
import '../models/semester.dart';
import 'ui_helpers.dart';

// ============================================================================
// 新增 / 编辑一门课的表单。
//
// 用法：
//   final result = await Navigator.push<Course>(context, MaterialPageRoute(
//     builder: (_) => CourseEditPage(initial: null, semester: ..., maxNode: 6),
//   ));
//   // result 为 null 表示用户取消了
//
// 页面上所有「选一个」的地方都用下拉或按钮，需要打字的只有四个文本框，
// 尽量让录课这件事快点结束。
// ============================================================================

class CourseEditPage extends StatefulWidget {
  const CourseEditPage({
    super.key,
    required this.semester,
    required this.maxNode,
    this.initial,
    this.existingCourses = const <Course>[],
    this.initialDayOfWeek,
    this.initialNode,
  });

  /// 学期信息（决定「第几周」可选范围）。
  final Semester semester;

  /// 一天最多几节（决定节次下拉的范围）。
  final int maxNode;

  /// 要编辑的课程；传 null 表示新增。
  final Course? initial;

  /// 现有课程，用来检查时间冲突。
  final List<Course> existingCourses;

  /// 新增时预选的星期（比如从空白格子点进来）。
  final int? initialDayOfWeek;

  /// 新增时预选的节次。
  final int? initialNode;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _roomCtrl;

  late int _dayOfWeek;
  late int _node;
  late WeekRule _rule;
  late int _startWeek;
  late int _endWeek;
  late Set<int> _customWeeks;

  bool get _isEditing => widget.initial != null;

  int get _totalWeeks =>
      widget.semester.totalWeeks < 1 ? 20 : widget.semester.totalWeeks;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;

    _nameCtrl = TextEditingController(text: c?.courseName ?? '');
    _teacherCtrl = TextEditingController(text: c?.teacher ?? '');
    _codeCtrl = TextEditingController(text: c?.courseCode ?? '');
    _roomCtrl = TextEditingController(text: c?.classroom ?? '');

    _dayOfWeek = c?.dayOfWeek ?? widget.initialDayOfWeek ?? 1;
    _node = c?.node ?? widget.initialNode ?? 1;
    _rule = c?.weekRule ?? WeekRule.every;
    _startWeek = c?.startWeek ?? 1;
    _endWeek = c?.endWeek ?? _totalWeeks;
    _customWeeks = <int>{...?c?.customWeeks};

    // 节次下拉的范围要兜住已有数据，避免历史数据不在 1..maxNode 里时选不中。
    if (_node > widget.maxNode) {
      _node = widget.maxNode < 1 ? 1 : widget.maxNode;
    }
    if (_node < 1) _node = 1;

    // 文本框改了要重画页面，否则下面的「效果预览」不会跟着更新。
    // （TextFormField 自己会刷新，但它不会通知外面的页面。）
    _nameCtrl.addListener(_onTextChanged);
    _roomCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onTextChanged);
    _roomCtrl.removeListener(_onTextChanged);
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _codeCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 组装

  /// 把表单内容拼成一条 [Course]。
  Course _buildCourse() {
    final base = widget.initial;
    final isCustom = _rule == WeekRule.custom;
    final customWeeks = _customWeeks.toList()..sort();

    return Course(
      id: base?.id ?? nextCourseId(widget.existingCourses),
      courseName: _nameCtrl.text.trim(),
      teacher: _teacherCtrl.text.trim(),
      courseCode: _codeCtrl.text.trim(),
      dayOfWeek: _dayOfWeek,
      node: _node,
      weekRule: _rule,
      startWeek: isCustom ? (customWeeks.isEmpty ? 1 : customWeeks.first) : _startWeek,
      endWeek: isCustom ? (customWeeks.isEmpty ? 1 : customWeeks.last) : _endWeek,
      customWeeks: customWeeks,
      classroom: _roomCtrl.text.trim(),
      overrides: base?.overrides ?? const <int, bool>{},
    );
  }

  // ------------------------------------------------------------------ 校验

  String? _validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return '请填写课程名称';
    return null;
  }

  /// 校验并保存。有问题就弹提示，不关页面。
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_rule == WeekRule.custom && _customWeeks.isEmpty) {
      _toast('选了「自定义」，请至少点选一个上课周次');
      return;
    }
    if (_rule != WeekRule.custom && _endWeek < _startWeek) {
      _toast('结束周不能早于起始周');
      return;
    }

    final course = _buildCourse();

    // 同一格 + 周次重叠 = 真冲突，问一下再保存（单双周轮换是正常的，不会被拦）。
    final conflicts = findCourseConflicts(widget.existingCourses, course);
    if (conflicts.isNotEmpty && mounted) {
      final ok = await _askConflict(conflicts);
      if (ok != true) return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(course);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _askConflict(List<Course> conflicts) {
    final lines = conflicts.take(3).map(describeConflict).join('\n');
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这一格已经有课了'),
        content: Text(
          '$lines\n\n'
          '如果它们的周次其实不重叠（比如单周 / 双周各一门），那就没问题，可以继续保存。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('回去改'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍然保存'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCustom = _rule == WeekRule.custom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑课程' : '添加课程'),
        actions: <Widget>[
          TextButton(
            onPressed: _submit,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: <Widget>[
            _SectionTitle('基本信息', scheme: scheme),
            TextFormField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              validator: _validateName,
              decoration: const InputDecoration(
                labelText: '课程名称 *',
                hintText: '例如：高等数学B（上）',
                prefixIcon: Icon(Icons.book_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _teacherCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '任课教师',
                hintText: '例如：张老师',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _roomCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '教室',
                hintText: '例如：一教203',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: '课程代码（可不填）',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 22),
            _SectionTitle('上课时间', scheme: scheme),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dayOfWeek,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    decoration: const InputDecoration(
                      labelText: '星期',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (var d = 1; d <= 7; d++)
                        DropdownMenuItem<int>(
                          value: d,
                          child: Text(weekdayFull(d)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _dayOfWeek = v ?? 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _node,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    decoration: const InputDecoration(
                      labelText: '第几节',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (var n = 1; n <= (widget.maxNode < 1 ? 1 : widget.maxNode); n++)
                        DropdownMenuItem<int>(value: n, child: Text('第 $n 节')),
                    ],
                    onChanged: (v) => setState(() => _node = v ?? 1),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),
            _SectionTitle('上哪些周', scheme: scheme),
            SegmentedButton<WeekRule>(
              segments: <ButtonSegment<WeekRule>>[
                for (final rule in WeekRule.values)
                  ButtonSegment<WeekRule>(
                    value: rule,
                    label: Text(rule.label),
                  ),
              ],
              selected: <WeekRule>{_rule},
              onSelectionChanged: (selection) {
                final picked = selection.first;
                setState(() {
                  _rule = picked;
                  if (picked == WeekRule.custom && _customWeeks.isEmpty) {
                    // 从「每周 3-16 周」切到自定义时，帮用户先垫上原来的范围，
                    // 免得面对一片空白不知道点哪儿。
                    for (var w = _startWeek; w <= _endWeek; w++) {
                      _customWeeks.add(w);
                    }
                  }
                });
              },
            ),

            const SizedBox(height: 14),
            if (!isCustom)
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startWeek.clamp(1, _totalWeeks),
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                      decoration: const InputDecoration(
                        labelText: '起始周',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                      ),
                      items: _weekItems(),
                      onChanged: (v) => setState(() {
                        _startWeek = v ?? 1;
                        if (_endWeek < _startWeek) _endWeek = _startWeek;
                      }),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('到'),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _endWeek.clamp(1, _totalWeeks),
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                      decoration: const InputDecoration(
                        labelText: '结束周',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                      ),
                      items: _weekItems(),
                      onChanged: (v) => setState(() => _endWeek = v ?? _totalWeeks),
                    ),
                  ),
                ],
              )
            else ...<Widget>[
              Text(
                '点一下要上课的周次（已选 ${_customWeeks.length} 周）',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (var w = 1; w <= _totalWeeks; w++)
                    FilterChip(
                      label: Text('$w'),
                      selected: _customWeeks.contains(w),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _customWeeks.add(w);
                        } else {
                          _customWeeks.remove(w);
                        }
                      }),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 18),
            _PreviewCard(course: () {
              // 实时预览：让用户在保存前就看到「这门课到底哪几周上」。
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return null;
              return _buildCourse();
            }()),

            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check),
                    label: const Text('保存这门课'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 周次下拉的选项。字写小一点、去掉空格，才塞得进手机上半宽的输入框。
  List<DropdownMenuItem<int>> _weekItems() => <DropdownMenuItem<int>>[
    for (var w = 1; w <= _totalWeeks; w++)
      DropdownMenuItem<int>(
        value: w,
        child: Text('第$w周', style: const TextStyle(fontSize: 13)),
      ),
  ];
}

// ---------------------------------------------------------------------- 小组件

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部的实时预览：把当前填的东西翻译成一句人话 + 周次列表。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.course});

  final Course? course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = course;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.visibility_outlined, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '效果预览',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (c == null)
            Text(
              '填上课程名称就能看到预览',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            )
          else ...<Widget>[
            Text(
              '${c.courseName} · ${weekdayFull(c.dayOfWeek)} 第${c.node}节'
              '${c.classroom.isEmpty ? '' : ' · ${c.classroom}'}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _weeksSentence(c),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  static String _weeksSentence(Course c) {
    final weeks = c.weeks;
    if (weeks.isEmpty) return '没有任何一周要上这门课，检查一下周次设置';
    if (weeks.length == 1) return '只在第 ${weeks.first} 周上';
    return '共 ${weeks.length} 周要上：第 ${weeks.first}-${weeks.last} 周内的'
        '${c.weekRule == WeekRule.every ? '每一周' : c.weekRule.label}';
  }
}

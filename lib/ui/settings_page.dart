import 'package:flutter/material.dart';

import '../data/sample_schedule.dart';
import '../models/class_period.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../state/schedule_controller.dart';
import 'overrides_page.dart';
import 'share_page.dart';

// ============================================================================
// 设置页：学期信息 + 作息时间 + 危险操作。
//
// 这里的改动都只在本页里暂存，点了右上角「保存」才真正写进课表；
// 这样你可以随便试，改错了直接返回就行。
// ============================================================================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final ScheduleController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _campusCtrl;
  late final TextEditingController _semesterCtrl;

  late DateTime _week1Start;
  late int _totalWeeks;
  late List<ClassPeriod> _periods;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.controller.data;

    _campusCtrl = TextEditingController(text: data?.campus ?? '');
    _semesterCtrl = TextEditingController(
      text: data?.semester.name ?? '我的学期',
    );
    _week1Start = data?.semester.week1Start ?? DateTime.now();
    _totalWeeks = data?.semester.totalWeeks ?? 20;
    _periods = <ClassPeriod>[...?data?.periods];
  }

  @override
  void dispose() {
    _campusCtrl.dispose();
    _semesterCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 操作

  Future<void> _pickWeek1Start() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _week1Start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择「第 1 周的周一」',
      fieldLabelText: '日期',
    );
    if (picked != null) {
      setState(() => _week1Start = Semester.dateOnly(picked));
    }
  }

  /// 课表里最大的节次，用来给新加的节次编号。
  int get _nextNode {
    if (_periods.isEmpty) return 1;
    return _periods.map((p) => p.node).reduce((a, b) => a > b ? a : b) + 1;
  }

  void _addPeriod() {
    final node = _nextNode;
    setState(() {
      _periods.add(
        ClassPeriod(node: node, label: '第$node节', start: '', end: ''),
      );
      _periods.sort((a, b) => a.node.compareTo(b.node));
    });
  }

  void _removePeriod(int node) {
    setState(() => _periods.removeWhere((p) => p.node == node));
  }

  Future<void> _pickTime(int index, {required bool isStart}) async {
    final period = _periods[index];
    final current = ClassPeriod.minutesOf(isStart ? period.start : period.end);
    final initial = TimeOfDay(hour: current ~/ 60, minute: current % 60);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '第 ${period.node} 节的${isStart ? '开始' : '结束'}时间',
    );
    if (picked == null) return;

    final text =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _periods[index] = ClassPeriod(
        node: period.node,
        label: period.label,
        start: isStart ? text : period.start,
        end: isStart ? period.end : text,
      );
    });
  }

  Future<void> _openOverrides() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OverridesPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _openShare() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharePage(controller: widget.controller),
      ),
    );
    if (!mounted) return;
    // 导入可能整份换掉了课表，把本页暂存的表单同步一遍。
    setState(() {
      final data = widget.controller.data;
      _campusCtrl.text = data?.campus ?? '';
      _semesterCtrl.text = data?.semester.name ?? '我的学期';
      _week1Start = data?.semester.week1Start ?? DateTime.now();
      _totalWeeks = data?.semester.totalWeeks ?? 20;
      _periods = <ClassPeriod>[...?data?.periods];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    await widget.controller.updateCampus(_campusCtrl.text.trim());
    await widget.controller.updateSemester(
      Semester(
        name: _semesterCtrl.text.trim().isEmpty
            ? '我的学期'
            : _semesterCtrl.text.trim(),
        week1Start: _week1Start,
        totalWeeks: _totalWeeks,
      ),
    );
    await widget.controller.updatePeriods(_periods);

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('设置已保存')));
  }

  /// 恢复成「刚装好」的样子：课程清空，作息回到默认那一套。
  Future<void> _resetToDefault() async {
    final ok = await _confirm(
      title: '恢复初始设置？',
      message: '课程、学期设置、作息时间会全部回到刚装好的样子，'
          '相当于重新开始用一次这个 App。这个操作没法撤销。',
      confirmText: '恢复初始',
    );
    if (ok != true) return;

    await widget.controller.resetToDefault();
    if (!mounted) return;
    _syncFromController();
    _toast('已恢复到初始状态');
  }

  /// 把控制器里的最新数据同步回本页的各个输入框。
  void _syncFromController() {
    setState(() {
      final data = widget.controller.data;
      _campusCtrl.text = data?.campus ?? '';
      _semesterCtrl.text = data?.semester.name ?? '我的学期';
      _week1Start = data?.semester.week1Start ?? DateTime.now();
      _totalWeeks = data?.semester.totalWeeks ?? 20;
      _periods = <ClassPeriod>[...?data?.periods];
    });
  }

  /// 装上内置的示例课表：自己先体验一下，或者当面演示给别人看。
  ///
  /// 它是**替换**而不是合并 —— 所以要先说清楚现有课表会被盖掉，
  /// 并提醒想留的话可以先导出分享码备份。
  Future<void> _loadSample() async {
    final ok = await _confirm(
      title: '装入示例课表？',
      message: '现在课表里的课程会被示例课表替换掉'
          '（示例里的老师和教室都是虚构的）。\n\n'
          '想留着现在这份的话，先点「取消」，到「分享码」那里导出一份备份。',
      confirmText: '装入示例',
    );
    if (ok != true) return;

    final sample = await loadSampleSchedule();
    if (!mounted) return;
    if (sample == null) {
      _toast('示例课表读取失败，重新装一次 App 试试');
      return;
    }

    await widget.controller.replaceAll(sample);
    if (!mounted) return;
    _syncFromController();
    _toast('已装入示例课表');
  }

  Future<void> _clearCourses() async {
    final ok = await _confirm(
      title: '清空所有课程？',
      message: '只会删掉课程，学期设置和作息时间会保留。之后你可以自己重新录入。',
      confirmText: '清空课程',
    );
    if (ok != true) return;

    final data = widget.controller.data;
    if (data == null) return;
    await widget.controller.replaceAll(
      data.copyWith(courses: const <Course>[]),
    );
    if (!mounted) return;
    _toast('已清空所有课程');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewMonday = _week1Start;
    final previewSunday = previewMonday.add(Duration(days: 6 * _totalWeeks - 1));
    final preview = Semester(
      name: _semesterCtrl.text,
      week1Start: _week1Start,
      totalWeeks: _totalWeeks,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          _SectionTitle('学期信息', scheme: scheme),
          TextField(
            controller: _campusCtrl,
            decoration: const InputDecoration(
              labelText: '学校 / 校区（可不填）',
              hintText: '例如：某某大学',
              prefixIcon: Icon(Icons.school_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _semesterCtrl,
            decoration: const InputDecoration(
              labelText: '学期名称',
              hintText: '例如：2026-2027 秋季学期',
              prefixIcon: Icon(Icons.event_note_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _PickerTile(
            icon: Icons.calendar_month_outlined,
            label: '第 1 周的周一',
            value: Semester.formatDate(_week1Start),
            hint: '点这里选日期',
            onTap: _pickWeek1Start,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _totalWeeks.clamp(1, 30),
            decoration: const InputDecoration(
              labelText: '学期总周数',
              prefixIcon: Icon(Icons.timelapse_outlined),
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<int>>[
              for (var w = 1; w <= 30; w++)
                DropdownMenuItem<int>(value: w, child: Text('$w 周')),
            ],
            onChanged: (v) => setState(() => _totalWeeks = v ?? 20),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '按现在的设置，这个学期从 ${Semester.formatDate(previewMonday)}'
              ' 上到 ${Semester.formatDate(previewSunday)}，'
              '今天是第 ${preview.currentWeek()} 周。',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),

          const SizedBox(height: 26),
          _SectionTitle('分享与导入', scheme: scheme),
          Text(
            '把自己的课表变成一段分享码发给同学，或者把同学发来的分享码、'
            '教务系统复制的课表文字导入进来。全程不联网。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openShare,
            icon: const Icon(Icons.qr_code_2_outlined),
            label: const Text('分享码 / 导入课表'),
          ),

          const SizedBox(height: 26),
          _SectionTitle('特殊日期（调休）', scheme: scheme),
          Text(
            '国庆放假、调休补课这类日子，可以按周单独调整哪几节课上、哪几节不上。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openOverrides,
            icon: const Icon(Icons.event_repeat_outlined),
            label: const Text('打开调休 / 临时调整'),
          ),

          const SizedBox(height: 30),
          _SectionTitle('作息时间', scheme: scheme),
          Text(
            '上下课时间会显示在课表左侧，也用来判断「现在上哪一节」。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_periods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有节次，点下面的按钮加一节。',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < _periods.length; i++)
            _PeriodTile(
              period: _periods[i],
              onPickStart: () => _pickTime(i, isStart: true),
              onPickEnd: () => _pickTime(i, isStart: false),
              onRemove: () => _removePeriod(_periods[i].node),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _addPeriod,
            icon: const Icon(Icons.add),
            label: Text('添加第 $_nextNode 节'),
          ),

          const SizedBox(height: 30),
          _SectionTitle('危险操作', scheme: scheme, danger: true),
          OutlinedButton.icon(
            onPressed: _loadSample,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('装入示例课表'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _resetToDefault,
            icon: const Icon(Icons.restart_alt),
            label: const Text('恢复初始设置'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _clearCourses,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('清空所有课程'),
          ),
          const SizedBox(height: 16),
          Text(
            '课表只存在这台手机里，不会上传到任何地方，也不需要联网。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- 小组件

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.scheme, this.danger = false});

  final String text;
  final ColorScheme scheme;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: danger ? scheme.error : scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: danger ? scheme.error : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value.isEmpty ? hint : value,
                style: TextStyle(
                  fontSize: 15,
                  color: value.isEmpty ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
            Icon(Icons.edit_outlined, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.period,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRemove,
  });

  final ClassPeriod period;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              '${period.node}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TimeButton(
              label: '开始',
              value: period.start,
              onTap: onPickStart,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('—'),
          ),
          Expanded(
            child: _TimeButton(
              label: '结束',
              value: period.end,
              onTap: onPickEnd,
            ),
          ),
          IconButton(
            tooltip: '删掉这一节',
            onPressed: onRemove,
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = value.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
            Text(
              empty ? '--:--' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

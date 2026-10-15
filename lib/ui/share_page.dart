import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../data/schedule_data.dart';
import '../logic/schedule_editor.dart';
import '../logic/schedule_parser.dart';
import '../logic/share_code.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../state/schedule_controller.dart';
import 'ui_helpers.dart';

// ============================================================================
// 阶段 5 的主角：分享与导入。
//
// 两个方向：
//   · 「分享给同学」——把课表压成一段短码，复制发出去；
//   · 「导入课表」  ——把同学发来的短码（或从教务系统复制的文本）粘回来。
//
// 全程不联网：码本身**就是**数据，微信、QQ、短信怎么传都行。
// ============================================================================

class SharePage extends StatefulWidget {
  const SharePage({super.key, required this.controller, this.initialTab = 0});

  final ScheduleController controller;

  /// 一打开停在哪个标签：0 = 分享给同学，1 = 导入课表。
  /// 从空课表页点「从教务系统导入」进来时，直接停在导入那一页。
  final int initialTab;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  final TextEditingController _inputCtrl = TextEditingController();

  late String _code;

  /// 粘贴后解析出来的预览，还没真正导入。
  _Preview? _preview;

  /// 上一次解析输入框内容时的文本，用来判断要不要清掉旧预览。
  String _lastInput = '';

  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _code = _buildCode();
    _inputCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    // 输入框内容一变，之前那次解析的结果就不再对应当前内容了，先收起来。
    if (_inputCtrl.text != _lastInput && _preview != null) {
      setState(() => _preview = null);
    }
  }

  ScheduleData? get _data => widget.controller.data;

  String _buildCode() {
    final data = _data;
    if (data == null) return '';
    return ShareCode.encode(data);
  }

  // ---------------------------------------------------------------- 分享

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    _toast('分享码已复制，去微信粘贴发给同学吧');
  }

  // ---------------------------------------------------------------- 导入

  /// 认一下这段文本是什么：分享码还是课表文本。
  void _analyze() {
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty) {
      _toast('先把同学发来的分享码粘贴进来');
      return;
    }

    final data = _data;
    if (data == null) return;

    _lastInput = _inputCtrl.text;

    // 分享码：带前缀，或者干脆整段就是 Base64 的样子。
    final looksLikeCode =
        raw.contains(kShareCodePrefix) ||
        RegExp(r'^[A-Za-z0-9_\-+/=\s]+$').hasMatch(raw);

    if (looksLikeCode) {
      try {
        final decoded = ShareCode.decode(raw);
        setState(() {
          _preview = _Preview(
            data: decoded,
            kind: _PreviewKind.shareCode,
            unrecognized: const <String>[],
            lineCount: 0,
          );
        });
        return;
      } on ShareCodeException catch (e) {
        // 长得像分享码但解不开：如果里面还有中文，就再当课表文本试一次。
        if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(raw)) {
          _toast(e.message);
          setState(() => _preview = null);
          return;
        }
      }
    }

    // 课表文本。
    final result = parseScheduleText(
      raw,
      defaultTotalWeeks: data.semester.totalWeeks,
    );
    if (result.isEmpty) {
      setState(() => _preview = null);
      _toast('没能从这段文字里认出课程，检查一下是不是复制全了');
      return;
    }

    setState(() {
      _preview = _Preview(
        data: data.copyWith(
          courses: result.courses,
          // 文本里常常会带上别人的作息时间，我们只用其中的课程。
          periods: data.periods,
        ),
        kind: _PreviewKind.text,
        unrecognized: result.unrecognized,
        lineCount: result.lineCount,
      );
    });
  }

  Future<void> _applyImport({required bool replace}) async {
    final preview = _preview;
    final current = _data;
    if (preview == null || current == null) return;

    if (replace) {
      final ok = await _confirm(
        title: '用这份课表替换现在的？',
        message: '你现在手机上的 ${current.courses.length} 条课程安排会被全部清掉，'
            '换成导入的这份。学期设置也会一起换。这个操作没法撤销。',
        confirmText: '替换',
      );
      if (ok != true || !mounted) return;

      await widget.controller.importReplaceAll(preview.data);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _inputCtrl.clear();
        _lastInput = '';
        _code = _buildCode();
      });
      _toast('已替换为导入的课表');
      return;
    }

    setState(() => _importing = true);
    final result = await widget.controller.importMerge(preview.data);
    if (!mounted) return;
    setState(() {
      _importing = false;
      _preview = null;
      _inputCtrl.clear();
      _lastInput = '';
      _code = _buildCode();
    });

    final skipped = result.skipped;
    _toast(
      skipped == 0
          ? '已导入 ${result.added} 条课程安排'
          : '新增 ${result.added} 条，跳过 $skipped 条重复的',
    );
  }

  void _clearInput() {
    setState(() {
      _inputCtrl.clear();
      _preview = null;
      _lastInput = '';
    });
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

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分享与导入'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: '分享给同学'),
            Tab(text: '导入课表'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[_buildShareTab(), _buildImportTab()],
      ),
    );
  }

  Widget _buildShareTab() {
    final scheme = Theme.of(context).colorScheme;
    final data = _data;

    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final fits = ShareCode.fitsInQrCode(_code);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: <Widget>[
        Text(
          '把下面这段分享码发给同学，他在「导入课表」里一粘就能拿到你的课表。'
          '整段过程不联网，码本身就是数据。',
          style: TextStyle(fontSize: 13, height: 1.6, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),

        _SummaryCard(data: data),

        const SizedBox(height: 18),

        if (fits)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                children: <Widget>[
                  // 二维码必须在白底上才扫得出来，所以这里写死白色，
                  // 不跟随深色主题。
                  QrImageView(
                    data: _code,
                    version: QrVersions.auto,
                    size: 208,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '面对面时让同学直接扫这个',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '课表比较大（${ShareCode.payloadLength(_code)} 个字符），'
                    '超出了二维码能装下的范围。请直接把下面的分享码复制发给同学。',
                    style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('复制分享码'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '分享码（长按可以手动选中复制）',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 130),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _code,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '这份分享码包含了学期设置、作息时间和全部 ${data.courses.length} 条课程安排。'
          '同学导入时可以选择「合并」到自己课表里，也可以整份替换。',
          style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: <Widget>[
        Text(
          '两种东西都能粘：\n'
          '① 同学发来的分享码（KTB1 开头那一长串）；\n'
          '② 从教务系统网页 / App 复制的课表文字。',
          style: TextStyle(fontSize: 13, height: 1.7, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _inputCtrl,
          maxLines: 7,
          minLines: 4,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: '在这里长按 → 粘贴',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: _inputCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    onPressed: _clearInput,
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _analyze,
                icon: const Icon(Icons.search),
                label: const Text('识别一下'),
              ),
            ),
          ],
        ),

        if (preview != null) ...<Widget>[
          const SizedBox(height: 20),
          _PreviewCard(preview: preview),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _importing ? null : () => _applyImport(replace: false),
            icon: const Icon(Icons.merge_type),
            label: Text(
              _importing ? '正在导入…' : '合并进我的课表（推荐）',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _importing ? null : () => _applyImport(replace: true),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('整份替换我的课表'),
          ),
          const SizedBox(height: 8),
          Text(
            '「合并」= 保留你现在的课表，只把没有的补进来（重复的会自动跳过）；\n'
            '「替换」= 清空你现在的课表，完全变成导入的这份。',
            style: TextStyle(fontSize: 12, height: 1.7, color: scheme.onSurfaceVariant),
          ),
        ],

        const SizedBox(height: 26),
        const Divider(),
        const SizedBox(height: 14),
        Text(
          '从教务系统复制课表的小技巧',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '在教务系统的课表页面上，从「星期一」那一行开始拖选到页面底部，'
          '整段复制过来就行。只要能看出「星期几、第几节、哪些周、教室」'
          '这几样，都能认出来。每门课之间不要漏掉星期那两个字。',
          style: TextStyle(fontSize: 12, height: 1.7, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const SelectableText(
            '高等数学B（上） 周一 第1-2节 3-15周 教5-201 张三\n'
            '大学英语读写（1） 周四 第2节 3-17周(单) 东12-301 李四\n'
            '大学英语视听说（1） 周四 第2节 4-18周(双) 东12-301 李四',
            style: TextStyle(fontSize: 11.5, height: 1.7, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '像上面这样，一门课写一行就最稳妥。',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------- 小组件

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final ScheduleData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = data.courses.map((c) => c.courseName).toSet().length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            data.semester.name.isEmpty ? '我的学期' : data.semester.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '$names 门课 · ${data.courses.length} 条安排 · 共 ${data.semester.totalWeeks} 周\n'
            '开学第一周：${Semester.formatDate(data.semester.week1Start)}'
            '（周一）',
            style: TextStyle(fontSize: 12, height: 1.7, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

enum _PreviewKind { shareCode, text }

class _Preview {
  const _Preview({
    required this.data,
    required this.kind,
    required this.unrecognized,
    required this.lineCount,
  });

  final ScheduleData data;
  final _PreviewKind kind;
  final List<String> unrecognized;
  final int lineCount;
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final _Preview preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = preview.data;
    final names = data.courses.map((c) => c.courseName).toSet().length;
    final isCode = preview.kind == _PreviewKind.shareCode;

    // 合并/替换预览里的课表时，id 是临时的，这里重新排一下序看起来才顺。
    final sample = <Course>[...data.courses]..sort(compareCourses);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                isCode ? '认出这是一份课表分享码' : '从文字里认出了课表',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isCode
                ? '这是一份完整的课表：$names 门课、${data.courses.length} 条安排'
                : '读了 ${preview.lineCount} 行，认出 $names 门课、'
                      '${data.courses.length} 条安排',
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
          if (!isCode) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '周次规则会按文本里写的识别，认不出的部分会按「每周」处理。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          ...sample.take(6).map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '· ${c.courseName}  ${weekdayFull(c.dayOfWeek)}第${c.node}节  '
                '${c.ruleText}${c.classroom.isEmpty ? '' : '  ${c.classroom}'}',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          if (sample.length > 6)
            Text(
              '… 还有 ${sample.length - 6} 条',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),

          if (preview.unrecognized.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '有 ${preview.unrecognized.length} 段文字没认出来（不会导入）：',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
            const SizedBox(height: 4),
            ...preview.unrecognized.take(3).map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line.length > 60 ? '${line.substring(0, 60)}…' : line,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            if (preview.unrecognized.length > 3)
              Text(
                '…',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'data/file_schedule_store.dart';
import 'data/sample_schedule.dart';
import 'data/schedule_store.dart';
import 'state/schedule_controller.dart';
import 'ui/settings_page.dart';
import 'ui/share_page.dart';
import 'ui/week_grid_page.dart';

// ============================================================================
// App 的入口。
//
// 启动只做一件事：把本机存档读出来交给界面。
//   · 本机没有存档（= 第一次打开）→ 一份空课表，用户自己往里录；
//   · 本机有存档 → 直接用用户自己那份。
// 整个过程完全在本机完成，不联网、不需要任何权限。
// ============================================================================

void main() {
  runApp(const TimetableApp());
}

class TimetableApp extends StatefulWidget {
  const TimetableApp({super.key});

  @override
  State<TimetableApp> createState() => _TimetableAppState();
}

class _TimetableAppState extends State<TimetableApp> {
  ScheduleController? _controller;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 启动流程：建仓库 → 读课表 → 交给界面。
  Future<void> _bootstrap() async {
    final controller = ScheduleController(
      repository: ScheduleRepository(store: FileScheduleStore()),
    );
    await controller.load();

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  /// 把内置示例课表装进来，让第一次用的人先看到界面长什么样。
  ///
  /// 开学日期的校正逻辑都在 [loadSampleSchedule] 里，
  /// 设置页要用同一套，所以抽出去共用。
  Future<void> _loadSample() async {
    final controller = _controller;
    if (controller == null) return;

    final sample = await loadSampleSchedule();
    if (sample == null) {
      if (mounted) _toast('示例课表读取失败，重新装一次 App 试试');
      return;
    }

    await controller.replaceAll(sample);
    if (mounted) _toast('已装入示例课表，随便改都行');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的课表',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F6FB5),
        scaffoldBackgroundColor: const Color(0xFFFAF9F7),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 数据一变就重画：编辑完课程回到课表，你不需要手动刷新。
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final error = controller.error;
        if (error != null) {
          return _ErrorPage(message: error, onRetry: controller.load);
        }

        final data = controller.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return WeekGridPage(
          data: data,
          onDataChanged: controller.replaceAll,
          onLoadSample: _loadSample,
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsPage(controller: controller),
            ),
          ),
          onOpenShare: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SharePage(controller: controller),
            ),
          ),
          onOpenImport: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SharePage(controller: controller, initialTab: 1),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 40, color: scheme.error),
              const SizedBox(height: 12),
              const Text('课表数据读取失败', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

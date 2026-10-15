// 阶段 3「设置页」的自动化测试。
//
// 设置页改的是学期信息和作息时间，一旦错了整个课表的周次都会算歪，
// 所以这里重点验证「改完点保存，真的写进课表了」。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/state/schedule_controller.dart';
import 'package:my_timetable/ui/settings_page.dart';

String seedText() => File('assets/data/sample_schedule.json').readAsStringSync();

/// 把测试窗口设成手机大小（理由同 widget_test.dart）。
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 设置页最外层那个长列表。
///
/// 页面上不止一个 Scrollable（每个输入框内部也有一个，用来横向滚动文字），
/// 用 ListView 更精确。
Finder get pageList => find.byType(ListView);

/// 一直往下滚，直到 [finder] 能找到东西为止。
///
/// 为什么不用 `scrollUntilVisible`：它要求 finder 唯一匹配、滚动容器也唯一，
/// 而设置页两者都不满足（输入框内部也有 Scrollable）。
/// 自己滚反而更稳，而且能配合「带 .first 的 finder」（那种 finder 在
/// 一个都找不到时会直接抛异常，不能拿来判断存在性）。
Future<void> scrollFinderIntoView(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 15 && finder.evaluate().isEmpty; i++) {
    await tester.drag(pageList, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
}

/// 滚到目标可见再点。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollFinderIntoView(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 只滚动到目标可见，不点击。
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await scrollFinderIntoView(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// 建一个已加载好课表的控制器并把设置页打开。
Future<ScheduleController> pumpSettings(WidgetTester tester) async {
  usePhoneSurface(tester);

  final controller = ScheduleController(
    repository: ScheduleRepository(
      store: MemoryScheduleStore(),
      seedJson: seedText(),
    ),
  );
  await controller.load();

  await tester.pumpWidget(
    MaterialApp(home: SettingsPage(controller: controller)),
  );
  await tester.pumpAndSettle();

  return controller;
}

void main() {
  testWidgets('设置页能正常打开，三块内容都在', (tester) async {
    await pumpSettings(tester);

    expect(find.text('学期信息'), findsOneWidget);
    expect(find.text('分享与导入'), findsOneWidget);

    // 页面比以前长了，「作息时间」一开始在折叠线下面，得滚过去
    await scrollTo(tester, find.text('作息时间'));
    expect(find.text('作息时间'), findsOneWidget);

    // 「危险操作」在页面最下面，滚过去看一眼
    await scrollTo(tester, find.text('恢复初始设置'));
    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('清空所有课程'), findsOneWidget);
  });

  testWidgets('打开设置页没有任何布局报错', (tester) async {
    await pumpSettings(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改总周数并保存，课表真的变了', (tester) async {
    final controller = await pumpSettings(tester);
    expect(controller.data!.semester.totalWeeks, 20);

    // 总周数下拉
    await tapVisible(tester, find.byType(DropdownButtonFormField<int>).first);
    await tapVisible(tester, find.text('16 周').last);

    await tapVisible(tester, find.text('保存'));

    expect(controller.data!.semester.totalWeeks, 16);

    // 确认也落盘了
    final reloaded = await controller.repository.load();
    expect(reloaded.semester.totalWeeks, 16);
  });

  testWidgets('改学期名称并保存', (tester) async {
    final controller = await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '2026-2027 学年 秋季学期'),
      '2027 春季学期',
    );
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('保存'));

    expect(controller.data!.semester.name, '2027 春季学期');
  });

  testWidgets('添加一节作息时间并保存', (tester) async {
    final controller = await pumpSettings(tester);
    final before = controller.data!.periods.length;

    // 按钮上写着「添加第 7 节」（已有 6 节）
    await tapVisible(tester, find.textContaining('添加第'));

    await tapVisible(tester, find.text('保存'));

    expect(controller.data!.periods.length, before + 1);
    expect(
      controller.data!.periods.map((p) => p.node).toList(),
      List<int>.generate(before + 1, (i) => i + 1),
    );
  });

  testWidgets('删掉一节作息时间并保存', (tester) async {
    final controller = await pumpSettings(tester);
    final before = controller.data!.periods.length;

    // 注意：带 .first 的 finder 在「一个都没找到」时会直接抛异常，
    // 不能拿它做存在性判断，所以先滚到它出现，再用 .first 去点。
    final removeButtons = find.byTooltip('删掉这一节');
    await scrollFinderIntoView(tester, removeButtons);
    await tapVisible(tester, removeButtons.first);

    await tapVisible(tester, find.text('保存'));

    expect(controller.data!.periods.length, before - 1);
  });

  // 两个入口分两条测试跑：走「进去再退回来」的写法时，退回来那一刻
  // 底层页面还在做转场，find 会扑空，分开测反而更稳。
  testWidgets('从设置页能进「调休」页', (tester) async {
    await pumpSettings(tester);

    await tapVisible(tester, find.text('打开调休 / 临时调整'));

    expect(find.text('调休 / 临时调整'), findsOneWidget);
    expect(find.text('全部停课'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从设置页能进「分享与导入」页', (tester) async {
    await pumpSettings(tester);

    await tapVisible(tester, find.text('分享码 / 导入课表'));

    expect(find.text('分享与导入'), findsOneWidget);
    expect(find.text('导入课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「清空所有课程」要先确认，确认后课程清空但作息保留', (tester) async {
    final controller = await pumpSettings(tester);
    final periodCount = controller.data!.periods.length;

    await tapVisible(tester, find.text('清空所有课程'));
    expect(find.text('清空所有课程？'), findsOneWidget);

    // 先点取消，什么都不该发生
    await tapVisible(tester, find.text('取消'));
    expect(controller.data!.courses, isNotEmpty);

    // 再来一次，这次确认
    await tapVisible(tester, find.text('清空所有课程'));
    await tapVisible(tester, find.widgetWithText(FilledButton, '清空课程'));

    expect(controller.data!.courses, isEmpty);
    expect(controller.data!.periods.length, periodCount);
  });

  testWidgets('「恢复初始设置」能把我改过的都还原', (tester) async {
    final controller = await pumpSettings(tester);

    // 先清空课程
    await tapVisible(tester, find.text('清空所有课程'));
    await tapVisible(tester, find.widgetWithText(FilledButton, '清空课程'));
    expect(controller.data!.courses, isEmpty);

    // 再恢复初始（这份测试里的「初始」= 传入的那份课表）
    await tapVisible(tester, find.text('恢复初始设置'));
    await tapVisible(tester, find.widgetWithText(FilledButton, '恢复初始'));

    expect(controller.data!.courses.length, 16);
    expect(controller.data!.semester.totalWeeks, 20);
  });
}

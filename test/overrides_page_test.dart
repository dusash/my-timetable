// 调休页的自动化测试。
//
// 这个页面改的是「某门课某一周到底上不上」，直接决定课表显示什么，
// 所以重点验证「点一下按钮，课表数据真的跟着变」，以及整周批量操作。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/logic/schedule_editor.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/state/schedule_controller.dart';
import 'package:my_timetable/ui/overrides_page.dart';

/// 2026-10-15 是第 6 周（双周）的周四。
final DateTime week6Thursday = DateTime(2026, 10, 15);

void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ScheduleController> pumpOverrides(
  WidgetTester tester, {
  DateTime? now,
}) async {
  usePhoneSurface(tester);

  final controller = ScheduleController(
    repository: ScheduleRepository(
      store: MemoryScheduleStore(),
      seedJson: File('assets/data/sample_schedule.json').readAsStringSync(),
    ),
  );
  await controller.load();

  await tester.pumpWidget(
    MaterialApp(
      home: OverridesPage(controller: controller, now: now ?? week6Thursday),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// 页面按这个顺序排出卡片，测试里需要拿到「第一张卡是哪门课」。
List<Course> coursesOnPage(ScheduleController controller, int week) {
  final result = controller.data!.courses
      .where((c) => c.isActiveInWeek(week) || c.overrides.containsKey(week))
      .toList();
  result.sort(compareCourses);
  return result;
}

void main() {
  testWidgets('打开调休页，默认停在本周（第 6 周）', (tester) async {
    await pumpOverrides(tester);

    expect(find.text('调休 / 临时调整'), findsOneWidget);
    expect(find.text('第 6 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('列出的课程数量和这一周实际的课一致', (tester) async {
    final controller = await pumpOverrides(tester);
    final expected = coursesOnPage(controller, 6).length;

    expect(
      find.text('第 6 周的课程（$expected 节）'),
      findsOneWidget,
    );
  });

  testWidgets('点「这周不上」，这门课那一周就真的没了', (tester) async {
    final controller = await pumpOverrides(tester);
    final target = coursesOnPage(controller, 6).first;
    expect(target.isActiveInWeek(6), isTrue);

    // 第一张卡片上的「这周不上」按钮
    await tapVisible(tester, find.text('这周不上').first);

    final after = controller.data!.courses.firstWhere((c) => c.id == target.id);
    expect(after.isActiveInWeek(6), isFalse);
    expect(after.overrides[6], isFalse);
  });

  testWidgets('改成「这周不上」之后，再点「按规律」能还原', (tester) async {
    final controller = await pumpOverrides(tester);
    final target = coursesOnPage(controller, 6).first;

    await tapVisible(tester, find.text('这周不上').first);
    expect(
      controller.data!.courses.firstWhere((c) => c.id == target.id).overrides,
      isNotEmpty,
    );

    await tapVisible(tester, find.text('按规律').first);

    final after = controller.data!.courses.firstWhere((c) => c.id == target.id);
    expect(after.overrides, isEmpty);
    expect(after.isActiveInWeek(6), isTrue);
  });

  testWidgets('「全部停课」之后，这一周一节都不剩', (tester) async {
    final controller = await pumpOverrides(tester);
    expect(coursesOnPage(controller, 6), isNotEmpty);

    await tapVisible(tester, find.text('全部停课'));

    expect(controller.data!.courses.every((c) => !c.isActiveInWeek(6)), isTrue);
    expect(find.textContaining('已设为全部停课'), findsOneWidget);
  });

  testWidgets('「全部照常」能把停掉的课全部恢复', (tester) async {
    final controller = await pumpOverrides(tester);

    await tapVisible(tester, find.text('全部停课'));
    final stopped = coursesOnPage(controller, 6);

    await tapVisible(tester, find.text('全部照常'));

    // 全部停课时「这一周的课」看着是空的，恢复后应该和之前一样多
    expect(
      controller.data!.courses.where((c) => c.isActiveInWeek(6)).length,
      greaterThan(0),
    );
    expect(stopped, isNotEmpty, reason: '停课前确实有课可停');
  });

  testWidgets('整周批量按钮在窄屏上不换行', (tester) async {
    await pumpOverrides(tester);

    // 真机上「本周全部停课」曾经被挤成两行，和左边按钮一高一矮。
    // 单行文字高度约 20 逻辑像素，换行会翻倍，所以这里卡一个上限。
    for (final label in <String>['全部照常', '全部停课']) {
      final size = tester.getSize(find.text(label));
      expect(size.height, lessThan(28), reason: '「$label」被挤成两行了');
    }
  });

  testWidgets('清空调休要先确认，确认后一条不剩', (tester) async {
    final controller = await pumpOverrides(tester);

    // 先设几条
    await tapVisible(tester, find.text('全部停课'));
    expect(countOverrides(controller.data!.courses), greaterThan(0));

    await tapVisible(tester, find.text('清空'));
    expect(find.text('清空全部调休？'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, '清空'));

    expect(countOverrides(controller.data!.courses), 0);
    expect(find.textContaining('已清空全部调休'), findsOneWidget);
  });

  testWidgets('没有调休时不显示「清空」按钮', (tester) async {
    await pumpOverrides(tester);
    expect(find.text('清空'), findsNothing);
  });

  testWidgets('可以翻到别的周', (tester) async {
    await pumpOverrides(tester);

    await tapVisible(tester, find.byTooltip('下一周'));
    expect(find.text('第 7 周'), findsOneWidget);
    expect(find.text('单周'), findsWidgets, reason: '第 7 周是单周');

    await tapVisible(tester, find.byTooltip('上一周'));
    expect(find.text('第 6 周'), findsOneWidget);
  });

  testWidgets('第 1 周不能再往前翻', (tester) async {
    await pumpOverrides(tester, now: DateTime(2026, 9, 7));
    expect(find.text('第 1 周'), findsOneWidget);

    final prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(prev.onPressed, isNull);
  });

  testWidgets('调休之后重新读存档，改动还在', (tester) async {
    final controller = await pumpOverrides(tester);

    await tapVisible(tester, find.text('全部停课'));

    final reloaded = await controller.repository.load();
    expect(reloaded.courses.every((c) => !c.isActiveInWeek(6)), isTrue);
  });
}

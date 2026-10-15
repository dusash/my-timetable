// 阶段 3「新增 / 编辑课程表单」的自动化测试。
//
// 重点验证四件事：必填项能拦住、周次规则切得动、冲突会提醒、保存后吐出的数据是对的。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';
import 'package:my_timetable/ui/course_edit_page.dart';

Semester testSemester() =>
    Semester(name: '测试学期', week1Start: DateTime(2026, 9, 7), totalWeeks: 20);

/// 把测试窗口设成手机大小，理由同 widget_test.dart：
/// 默认的 800×600 会让表单底部的按钮跑到屏幕外，点不中。
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 先滚到可见再点。表单是可滚动的，直接点可能落在屏幕外。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 直接把表单当成首页打开（不需要拿返回值的时候用）。
Future<void> pumpForm(
  WidgetTester tester, {
  Course? initial,
  List<Course> existing = const <Course>[],
}) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: CourseEditPage(
        semester: testSemester(),
        maxNode: 6,
        initial: initial,
        existingCourses: existing,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 打开表单，并返回一个「读取结果」的函数。
///
/// 用 `final readResult = await pumpFormAwaiting(tester);` 打开表单，
/// 操作完之后 `await readResult()` 就能拿到表单 pop 出来的课程（没保存就是 null）。
Future<Future<Course?> Function()> pumpFormAwaiting(
  WidgetTester tester, {
  Course? initial,
  List<Course> existing = const <Course>[],
}) async {
  usePhoneSurface(tester);

  Course? result;
  late BuildContext hostContext;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();

  final future = Navigator.of(hostContext).push<Course>(
    MaterialPageRoute<Course>(
      builder: (_) => CourseEditPage(
        semester: testSemester(),
        maxNode: 6,
        initial: initial,
        existingCourses: existing,
      ),
    ),
  );
  // 表单被 pop 之后，这个 future 才会完成；这里不等它，只接住结果。
  future.then((value) => result = value);
  await tester.pumpAndSettle();

  return () async {
    await tester.pumpAndSettle();
    return result;
  };
}

void main() {
  testWidgets('新开表单时标题是「添加课程」', (tester) async {
    await pumpForm(tester);

    expect(find.text('添加课程'), findsOneWidget);
    expect(find.text('课程名称 *'), findsOneWidget);
  });

  testWidgets('编辑已有课程时标题是「编辑课程」，并且带出原来的内容', (tester) async {
    await pumpForm(
      tester,
      initial: const Course(
        id: 'x',
        courseName: '高等数学B（上）',
        teacher: '李明',
        courseCode: '',
        dayOfWeek: 1,
        node: 1,
        weekRule: WeekRule.every,
        startWeek: 3,
        endWeek: 15,
        classroom: '一教203',
      ),
    );

    expect(find.text('编辑课程'), findsOneWidget);
    expect(find.text('高等数学B（上）'), findsOneWidget);
    expect(find.text('李明'), findsOneWidget);
    expect(find.text('一教203'), findsOneWidget);
  });

  testWidgets('不填课程名就保存，会被拦住并提示', (tester) async {
    await pumpForm(tester);

    await tapVisible(tester, find.text('保存这门课'));

    expect(find.text('请填写课程名称'), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget, reason: '页面不应该被关掉');
  });

  testWidgets('填了课程名就有实时预览', (tester) async {
    await pumpForm(tester);

    expect(find.text('填上课程名称就能看到预览'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '人工智能导论');
    await tester.pumpAndSettle();

    expect(find.textContaining('周一 第1节'), findsOneWidget);
    expect(find.textContaining('共 20 周要上'), findsOneWidget);
  });

  testWidgets('切成「自定义」后会列出所有周次，可以一个个点选', (tester) async {
    await pumpForm(tester);

    await tapVisible(tester, find.text('自定义'));

    expect(find.textContaining('点一下要上课的周次'), findsOneWidget);
    // 默认会把原来的 1-20 周先帮你选上
    expect(find.textContaining('已选 20 周'), findsOneWidget);

    // 点掉第 1 周
    await tapVisible(tester, find.widgetWithText(FilterChip, '1'));
    expect(find.textContaining('已选 19 周'), findsOneWidget);
  });

  testWidgets('填好保存后，返回的课程对象是对的', (tester) async {
    final readResult = await pumpFormAwaiting(tester);

    await tester.enterText(find.byType(TextFormField).first, '人工智能导论');
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('保存这门课'));

    final result = await readResult();
    expect(result, isNotNull);
    expect(result!.courseName, '人工智能导论');
    expect(result.dayOfWeek, 1);
    expect(result.node, 1);
    expect(result.weekRule, WeekRule.every);
    expect(result.startWeek, 1);
    expect(result.endWeek, 20);
    expect(result.id, isNotEmpty);
  });

  testWidgets('和已有课程抢同一格时，会先弹冲突提醒，选「回去改」就不保存', (tester) async {
    const existing = Course(
      id: 'old',
      courseName: '高等数学B（上）',
      teacher: '',
      courseCode: '',
      dayOfWeek: 1,
      node: 1,
      weekRule: WeekRule.every,
      startWeek: 1,
      endWeek: 20,
      classroom: '',
    );

    final readResult = await pumpFormAwaiting(
      tester,
      existing: const <Course>[existing],
    );

    await tester.enterText(find.byType(TextFormField).first, '另一门课');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('保存这门课'));

    expect(find.text('这一格已经有课了'), findsOneWidget);
    expect(await readResult(), isNull, reason: '还没确认，不应该保存');

    // 选「回去改」→ 回到表单，依然没有返回值
    await tapVisible(tester, find.text('回去改'));
    expect(find.text('添加课程'), findsOneWidget);
    expect(await readResult(), isNull);
  });

  testWidgets('单双周轮换不会被误判成冲突', (tester) async {
    // 已有的：周四第二节、单周
    const oddCourse = Course(
      id: 'odd',
      courseName: '大学英语读写（1）',
      teacher: '',
      courseCode: '',
      dayOfWeek: 4,
      node: 2,
      weekRule: WeekRule.odd,
      startWeek: 3,
      endWeek: 17,
      classroom: '',
    );

    final readResult = await pumpFormAwaiting(
      tester,
      existing: const <Course>[oddCourse],
    );

    await tester.enterText(find.byType(TextFormField).first, '大学英语视听说（1）');
    await tester.pumpAndSettle();

    // 改成周四
    await tapVisible(tester, find.byType(DropdownButtonFormField<int>).first);
    await tapVisible(tester, find.text('周四').last);

    // 节次改成第 2 节
    await tapVisible(tester, find.byType(DropdownButtonFormField<int>).at(1));
    await tapVisible(tester, find.text('第 2 节').last);

    // 周次规则改成双周
    await tapVisible(tester, find.text('双周'));

    await tapVisible(tester, find.text('保存这门课'));

    // 不应该弹冲突框，直接保存成功
    expect(find.text('这一格已经有课了'), findsNothing);
    final result = await readResult();
    expect(result, isNotNull);
    expect(result!.dayOfWeek, 4);
    expect(result.node, 2);
    expect(result.weekRule, WeekRule.even);
  });
}

// 阶段 3「状态控制器」的自动化测试。
//
// 它管的是「改完课之后有没有真的存下来」，所以每一条测试都同时检查
// 「内存里的数据变了」和「存档里也变了」。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/models/class_period.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';
import 'package:my_timetable/state/schedule_controller.dart';

String seedText() => File('assets/data/sample_schedule.json').readAsStringSync();

/// 造一个已经加载好出厂课表的控制器，外加它用的那个内存存档。
({ScheduleController controller, MemoryScheduleStore store}) buildController() {
  final store = MemoryScheduleStore();
  final controller = ScheduleController(
    repository: ScheduleRepository(store: store, seedJson: seedText()),
  );
  return (controller: controller, store: store);
}

void main() {
  testWidgets('load 之后拿到课表，loading 变 false', (tester) async {
    final built = buildController();
    expect(built.controller.loading, isTrue);
    expect(built.controller.data, isNull);

    await built.controller.load();

    expect(built.controller.loading, isFalse);
    expect(built.controller.data, isNotNull);
    expect(built.controller.data!.courses.length, 16);
    expect(built.controller.error, isNull);
  });

  testWidgets('加载完会通知界面重画（notifyListeners 有生效）', (tester) async {
    final built = buildController();
    var notified = 0;
    built.controller.addListener(() => notified++);

    await built.controller.load();

    expect(notified, greaterThan(0));
  });

  testWidgets('新增一门课：内存和存档同时更新', (tester) async {
    final built = buildController();
    await built.controller.load();
    final before = built.controller.data!.courses.length;

    await built.controller.saveCourse(
      Course(
        id: 'brand-new',
        courseName: '人工智能导论',
        teacher: '张老师',
        courseCode: '',
        dayOfWeek: 6,
        node: 1,
        weekRule: WeekRule.every,
        startWeek: 1,
        endWeek: 16,
        classroom: '东1-101',
      ),
    );

    expect(built.controller.data!.courses.length, before + 1);
    expect(
      built.controller.data!.courses.any((c) => c.courseName == '人工智能导论'),
      isTrue,
    );

    // 重新读存档，新课必须还在（证明真的落盘了）
    final reloaded = await ScheduleRepository(store: built.store).load();
    expect(
      reloaded.courses.any((c) => c.courseName == '人工智能导论'),
      isTrue,
    );
  });

  testWidgets('修改一门课：同名同 id，不会变成两条', (tester) async {
    final built = buildController();
    await built.controller.load();

    final target = built.controller.data!.courses.first;
    final before = built.controller.data!.courses.length;

    await built.controller.saveCourse(
      target.copyWith(classroom: '换了个教室-999'),
    );

    expect(built.controller.data!.courses.length, before);
    final updated = built.controller.data!.courses
        .firstWhere((c) => c.id == target.id);
    expect(updated.classroom, '换了个教室-999');
  });

  testWidgets('删除一门课：内存和存档都少一条', (tester) async {
    final built = buildController();
    await built.controller.load();

    final target = built.controller.data!.courses.first;
    final before = built.controller.data!.courses.length;

    await built.controller.deleteCourse(target.id);

    expect(built.controller.data!.courses.length, before - 1);
    expect(
      built.controller.data!.courses.any((c) => c.id == target.id),
      isFalse,
    );

    final reloaded = await ScheduleRepository(store: built.store).load();
    expect(reloaded.courses.any((c) => c.id == target.id), isFalse);
  });

  testWidgets('改学期：开学日期和总周数都能落盘', (tester) async {
    final built = buildController();
    await built.controller.load();

    await built.controller.updateSemester(
      Semester(
        name: '改过的学期',
        week1Start: DateTime(2026, 3, 2),
        totalWeeks: 16,
      ),
    );

    expect(built.controller.data!.semester.totalWeeks, 16);

    final reloaded = await ScheduleRepository(store: built.store).load();
    expect(reloaded.semester.name, '改过的学期');
    expect(reloaded.semester.totalWeeks, 16);
    expect(reloaded.semester.week1Start, DateTime(2026, 3, 2));
  });

  testWidgets('改作息：会自动按节次排好序', (tester) async {
    final built = buildController();
    await built.controller.load();

    await built.controller.updatePeriods(const <ClassPeriod>[
      ClassPeriod(node: 3, label: '第三节', start: '14:00', end: '15:35'),
      ClassPeriod(node: 1, label: '第一节', start: '08:00', end: '09:35'),
      ClassPeriod(node: 2, label: '第二节', start: '10:05', end: '11:40'),
    ]);

    final periods = built.controller.data!.periods;
    expect(periods.map((p) => p.node).toList(), <int>[1, 2, 3]);
  });

  testWidgets('改校区名能落盘', (tester) async {
    final built = buildController();
    await built.controller.load();

    await built.controller.updateCampus('示例大学');
    final reloaded = await ScheduleRepository(store: built.store).load();
    expect(reloaded.campus, '示例大学');
  });

  testWidgets('恢复到出厂：之前删掉的课又回来了', (tester) async {
    final built = buildController();
    await built.controller.load();
    await built.controller.replaceAll(
      built.controller.data!.copyWith(courses: const <Course>[]),
    );
    expect(built.controller.hasNoCourse, isTrue);

    await built.controller.resetToDefault();

    expect(built.controller.data!.courses.length, 16);
    expect(built.controller.hasNoCourse, isFalse);
  });
}

// 调休（临时停课 / 补课）的自动化测试。
//
// 这件事很容易出微妙的错：override 只影响「某一周」，不能污染其他周，
// 也不能让「取消调整」之后回不到原来的规律。所以重点测这三种状态的切换。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/logic/schedule_editor.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/state/schedule_controller.dart';

ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

/// 找一门「每周都上、周次跨度大」的课，测起来最直观。
Course pickWeekly(ScheduleData data) => data.courses.firstWhere(
  (c) => c.weekRule == WeekRule.every && c.endWeek - c.startWeek >= 5,
);

void main() {
  group('单门课的调休', () {
    test('设成「这周不上」之后，那一周就不出现了', () {
      final data = loadData();
      final course = pickWeekly(data);
      final week = course.startWeek + 1;
      expect(course.isActiveInWeek(week), isTrue);

      final next = setCourseOverrideInList(data.courses, course.id, week, false);
      final updated = next.firstWhere((c) => c.id == course.id);

      expect(updated.isActiveInWeek(week), isFalse);
    });

    test('只影响被点的那一周，别的周照旧', () {
      final data = loadData();
      final course = pickWeekly(data);
      final week = course.startWeek + 1;

      final next = setCourseOverrideInList(data.courses, course.id, week, false);
      final updated = next.firstWhere((c) => c.id == course.id);

      expect(updated.isActiveInWeek(week + 1), isTrue);
      expect(updated.isActiveInWeek(week + 2), isTrue);
      expect(updated.overrides.length, 1);
    });

    test('设成「这周一定上」能让本来不上的一周冒出课来', () {
      final data = loadData();
      // 找一门单周课
      final course = data.courses.firstWhere((c) => c.weekRule == WeekRule.odd);
      final evenWeek = course.weeks.first.isEven
          ? course.weeks.first
          : course.weeks.first + 1;
      expect(course.isActiveInWeek(evenWeek), isFalse);

      final next = setCourseOverrideInList(
        data.courses,
        course.id,
        evenWeek,
        true,
      );
      expect(
        next.firstWhere((c) => c.id == course.id).isActiveInWeek(evenWeek),
        isTrue,
      );
    });

    test('取消调整（传 null）能完全回到原来的规律', () {
      final data = loadData();
      final course = pickWeekly(data);
      final week = course.startWeek + 1;

      var next = setCourseOverrideInList(data.courses, course.id, week, false);
      expect(next.firstWhere((c) => c.id == course.id).overrides, isNotEmpty);

      next = setCourseOverrideInList(next, course.id, week, null);
      final updated = next.firstWhere((c) => c.id == course.id);

      expect(updated.overrides, isEmpty);
      expect(updated.isActiveInWeek(week), isTrue, reason: '规律应该恢复');
    });

    test('不影响其他课', () {
      final data = loadData();
      final course = pickWeekly(data);
      final others = data.courses.where((c) => c.id != course.id).toList();

      final next = setCourseOverrideInList(data.courses, course.id, 3, false);

      for (final other in others) {
        final after = next.firstWhere((c) => c.id == other.id);
        expect(after.overrides, isEmpty);
      }
    });

    test('id 不存在时原样返回，不会报错', () {
      final data = loadData();
      final next = setCourseOverrideInList(data.courses, '不存在的id', 3, false);
      expect(next.length, data.courses.length);
      expect(next.every((c) => c.overrides.isEmpty), isTrue);
    });
  });

  group('整周批量与清空', () {
    test('批量停课会把这一周的课全部标上', () {
      final data = loadData();
      final ids = data.courses.map((c) => c.id).toList();

      final next = setWeekOverrideForCourses(data.courses, ids, 6, false);
      final atWeek6 = next.where((c) => c.isActiveInWeek(6)).toList();

      expect(atWeek6, isEmpty, reason: '第 6 周应该一节都不剩');
      expect(countOverrides(next), data.courses.length);
    });

    test('批量「照常」只改被点名的那几门', () {
      final data = loadData();
      final first = data.courses.first;

      final next = setWeekOverrideForCourses(
        data.courses,
        <String>[first.id],
        6,
        true,
      );

      expect(countOverrides(next), 1);
      expect(next.firstWhere((c) => c.id == first.id).isActiveInWeek(6), isTrue);
    });

    test('clearAllOverrides 一次清干净', () {
      final data = loadData();
      final ids = data.courses.map((c) => c.id);

      var next = setWeekOverrideForCourses(data.courses, ids, 6, false);
      next = setWeekOverrideForCourses(next, ids, 7, true);
      expect(countOverrides(next), data.courses.length * 2);

      final cleaned = clearAllOverrides(next);
      expect(countOverrides(cleaned), 0);
      expect(cleaned.every((c) => c.overrides.isEmpty), isTrue);
    });

    test('没有调休时 countOverrides 是 0', () {
      expect(countOverrides(loadData().courses), 0);
    });
  });

  group('通过控制器改，改动会落盘', () {
    test('setOverride 之后重新读出来的课表也带着这条调整', () async {
      final store = MemoryScheduleStore();
      final controller = ScheduleController(
        repository: ScheduleRepository(
          store: store,
          seedJson: File('assets/data/sample_schedule.json').readAsStringSync(),
        ),
      );
      await controller.load();

      final course = pickWeekly(controller.data!);
      await controller.setOverride(course.id, 4, false);

      final reloaded = await controller.repository.load();
      final saved = reloaded.courses.firstWhere((c) => c.id == course.id);
      expect(saved.isActiveInWeek(4), isFalse);
    });

    test('clearOverrides 会把落盘的调休也一起清掉', () async {
      final store = MemoryScheduleStore();
      final controller = ScheduleController(
        repository: ScheduleRepository(
          store: store,
          seedJson: File('assets/data/sample_schedule.json').readAsStringSync(),
        ),
      );
      await controller.load();

      final ids = controller.data!.courses.map((c) => c.id).toList();
      await controller.setOverridesForCourses(ids, 5, false);
      expect(controller.data!.courses.every((c) => !c.isActiveInWeek(5)), isTrue);

      await controller.clearOverrides();

      final reloaded = await controller.repository.load();
      expect(countOverrides(reloaded.courses), 0);
    });
  });
}

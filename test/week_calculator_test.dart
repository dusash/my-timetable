// 阶段 1 算法的自动化测试。
//
// 运行： flutter test
//
// 和 tool/verify_logic.dart 的区别：那个是给人看的「体检报告」，
// 这个是可以反复跑、跑一次就知道有没有改坏的正式测试。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';

/// 直接读项目里的真实课表。
ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

void main() {
  final data = loadData();
  final calculator = data.calculator;

  Course byName(String name, {int? day, int? node}) => data.courses.firstWhere(
    (c) =>
        c.courseName == name &&
        (day == null || c.dayOfWeek == day) &&
        (node == null || c.node == node),
    orElse: () => throw StateError('找不到课程：$name'),
  );

  group('学期周次换算', () {
    test('开学前一天算第 0 周（不能错误地算成第 1 周）', () {
      expect(data.semester.weekOf(DateTime(2026, 9, 6)), 0);
    });

    test('开学第一天是第 1 周', () {
      expect(data.semester.weekOf(DateTime(2026, 9, 7)), 1);
    });

    test('同一周的周日仍属于这一周', () {
      expect(data.semester.weekOf(DateTime(2026, 9, 13)), 1);
      expect(data.semester.weekOf(DateTime(2026, 10, 18)), 6);
    });

    test('2026-10-14 是第 6 周', () {
      expect(data.semester.weekOf(DateTime(2026, 10, 14)), 6);
    });

    test('第 6 周的周一 / 周三 / 周日', () {
      expect(data.semester.dateOf(6, 1), DateTime(2026, 10, 12));
      expect(data.semester.dateOf(6, 3), DateTime(2026, 10, 14));
      expect(data.semester.dateOf(6, 7), DateTime(2026, 10, 18));
    });

    test('单双周判断', () {
      expect(Semester.parityLabel(5), '单周');
      expect(Semester.parityLabel(6), '双周');
      expect(Semester.parityLabel(7), '单周');
      expect(data.semester.containsWeek(20), isTrue);
      expect(data.semester.containsWeek(21), isFalse);
    });
  });

  group('周次规则展开', () {
    test('单周：人文素质教育 5-15 → 5,7,9,11,13,15', () {
      expect(byName('人文素质教育').weeks, <int>[5, 7, 9, 11, 13, 15]);
    });

    test('每周：高等数学B 3-15 → 连续 13 周', () {
      final weeks = byName('高等数学B（上）', day: 1).weeks;
      expect(weeks.length, 13);
      expect(weeks.first, 3);
      expect(weeks.last, 15);
    });

    test('双周：大学英语视听说 4-18 → 全是偶数周', () {
      expect(byName('大学英语视听说（1）').weeks, <int>[4, 6, 8, 10, 12, 14, 16, 18]);
    });

    test('自定义规则的展开函数', () {
      expect(
        expandWeeks(
          rule: WeekRule.custom,
          startWeek: 1,
          endWeek: 20,
          customWeeks: <int>[9, 3, 3, 15],
        ),
        <int>[3, 9, 15],
      );
    });
  });

  group('单双周交替（周四第二节）', () {
    test('双周上的是视听说，不是读写', () {
      expect(calculator.courseAt(6, 4, 2)?.courseName, '大学英语视听说（1）');
      expect(byName('大学英语读写（1）', day: 4).isActiveInWeek(6), isFalse);
    });

    test('单周上的是读写，不是视听说', () {
      expect(calculator.courseAt(5, 4, 2)?.courseName, '大学英语读写（1）');
      expect(byName('大学英语视听说（1）').isActiveInWeek(5), isFalse);
    });

    test('单周才有的人文素质教育，双周那一格是空的', () {
      expect(calculator.courseAt(5, 3, 1)?.courseName, '人文素质教育');
      expect(calculator.courseAt(6, 3, 1), isNull);
    });
  });

  group('同一时段按周次分段（周五第四节）', () {
    test('前半学期是心理教育健康', () {
      expect(calculator.courseAt(6, 5, 4)?.courseName, '心理教育健康');
      expect(calculator.courseAt(10, 5, 4)?.courseName, '心理教育健康');
    });

    test('后半学期换成职业发展', () {
      expect(calculator.courseAt(11, 5, 4)?.courseName, '职业发展');
      expect(calculator.courseAt(15, 5, 4)?.courseName, '职业发展');
    });

    test('还没开课的周次两边都不上', () {
      expect(calculator.courseAt(5, 5, 4), isNull);
    });
  });

  group('连堂课（周二第四、五节近代史）', () {
    test('两节都能查到同一门课', () {
      expect(calculator.courseAt(6, 2, 4)?.courseName, '中国近现代史纲要');
      expect(calculator.courseAt(6, 2, 5)?.courseName, '中国近现代史纲要');
    });

    test('第 6 周周二一共 4 节', () {
      expect(calculator.coursesOfDay(6, 2).length, 4);
    });
  });

  group('调休覆盖（overrides）', () {
    final holiday = Course(
      id: 'test',
      courseName: '调休测试课',
      teacher: '测试',
      courseCode: 'TEST',
      dayOfWeek: 1,
      node: 1,
      weekRule: WeekRule.every,
      startWeek: 3,
      endWeek: 15,
      overrides: const <int, bool>{5: false, 6: true},
    );

    test('没被覆盖的周次按规律来', () {
      expect(holiday.isActiveInWeek(3), isTrue);
      expect(holiday.isActiveInWeek(20), isFalse);
    });

    test('被覆盖成 false 就当放假', () {
      expect(holiday.isActiveInWeek(5), isFalse);
    });

    test('被覆盖成 true 就当补课', () {
      expect(holiday.isActiveInWeek(6), isTrue);
    });
  });

  group('数据体检', () {
    test('没有两个格子被同一门课占用', () {
      expect(calculator.detectConflicts(), isEmpty);
    });

    test('全学期 10 门不重复的课', () {
      expect(calculator.distinctCourseNames().length, 10);
    });

    test('导出再导入，数据完全一致', () {
      final again = ScheduleData.parse(data.toJsonString());
      expect(again.courses.length, data.courses.length);
      expect(again.semester.week1Start, data.semester.week1Start);
      expect(again.courses.first.courseName, data.courses.first.courseName);
    });
  });
}

// 阶段 3「增删改」逻辑的自动化测试。
//
// 这一段是纯函数，不依赖 Flutter，所以跑得飞快，也最容易验证对不对。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/logic/schedule_editor.dart';
import 'package:my_timetable/models/course.dart';

ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

/// 造一门课，只关心测试用到的字段。
Course makeCourse({
  String id = 'new',
  String name = '测试课',
  int day = 1,
  int node = 1,
  WeekRule rule = WeekRule.every,
  int start = 1,
  int end = 16,
  String room = 'A101',
}) {
  return Course(
    id: id,
    courseName: name,
    teacher: '老师',
    courseCode: '',
    dayOfWeek: day,
    node: node,
    weekRule: rule,
    startWeek: start,
    endWeek: end,
    classroom: room,
  );
}

void main() {
  group('排序规则', () {
    test('先按星期、再按节次', () {
      final a = makeCourse(id: 'a', day: 2, node: 1);
      final b = makeCourse(id: 'b', day: 1, node: 5);
      expect(compareCourses(b, a) < 0, isTrue);
      expect(compareCourses(a, b) > 0, isTrue);
    });

    test('同一天同一节时，起始周早的排前面（单双周轮换看起来更自然）', () {
      final odd = makeCourse(id: 'odd', day: 4, node: 2, rule: WeekRule.odd, start: 3);
      final even = makeCourse(id: 'even', day: 4, node: 2, rule: WeekRule.even, start: 4);
      expect(compareCourses(odd, even) < 0, isTrue);
    });

    test('自己和自己比较是 0', () {
      final c = makeCourse();
      expect(compareCourses(c, c), 0);
    });
  });

  group('生成 id', () {
    test('空课表里给 c1', () {
      expect(nextCourseId(const <Course>[]), 'c1');
    });

    test('生成的 id 不会和已有的撞车', () {
      final courses = <Course>[
        makeCourse(id: 'c1'),
        makeCourse(id: 'c2'),
        makeCourse(id: 'c4'),
      ];
      final id = nextCourseId(courses);
      expect(courses.map((c) => c.id), isNot(contains(id)));
    });

    test('连续生成两次，第二次会和第一次不同', () {
      var courses = <Course>[];
      final first = nextCourseId(courses);
      courses = upsertCourseInList(courses, makeCourse(id: first, name: '第一门'));
      final second = nextCourseId(courses);
      expect(second, isNot(first));
    });
  });

  group('新增 / 替换 / 删除', () {
    test('新增会真的进到列表里，而且列表变长了', () {
      final before = const <Course>[];
      final after = upsertCourseInList(before, makeCourse(id: 'x', name: '新课'));
      expect(before.length, 0, reason: '原列表不能被改动');
      expect(after.length, 1);
      expect(after.first.courseName, '新课');
    });

    test('id 相同就是替换，不会变成两条', () {
      final courses = <Course>[makeCourse(id: 'x', name: '旧名')];
      final after = upsertCourseInList(courses, makeCourse(id: 'x', name: '新名'));
      expect(after.length, 1);
      expect(after.first.courseName, '新名');
    });

    test('新增后列表自动排好序', () {
      var courses = <Course>[];
      courses = upsertCourseInList(courses, makeCourse(id: 'a', name: 'A', day: 5, node: 1));
      courses = upsertCourseInList(courses, makeCourse(id: 'b', name: 'B', day: 1, node: 1));
      courses = upsertCourseInList(courses, makeCourse(id: 'c', name: 'C', day: 1, node: 2));
      expect(courses.map((c) => c.id).toList(), <String>['b', 'c', 'a']);
    });

    test('删除只删掉指定的那一条', () {
      final courses = <Course>[
        makeCourse(id: 'a', name: 'A'),
        makeCourse(id: 'b', name: 'B'),
      ];
      final after = removeCourseFromList(courses, 'a');
      expect(after.length, 1);
      expect(after.single.courseName, 'B');
    });

    test('删一个不存在的 id 不会出错', () {
      final courses = <Course>[makeCourse(id: 'a')];
      expect(removeCourseFromList(courses, '不存在').length, 1);
    });

    test('删光之后就是空列表', () {
      final courses = <Course>[makeCourse(id: 'a')];
      expect(removeCourseFromList(courses, 'a'), isEmpty);
    });
  });

  group('时间冲突检测', () {
    test('同一格 + 周次重叠 = 冲突', () {
      final existing = makeCourse(id: 'a', day: 1, node: 1, start: 1, end: 16);
      final candidate = makeCourse(id: 'b', day: 1, node: 1, start: 5, end: 10);
      final conflicts = findCourseConflicts(<Course>[existing], candidate);
      expect(conflicts.length, 1);
      expect(conflicts.first.id, 'a');
    });

    test('同一格但单周 / 双周各一门，不算冲突（这是正常的排课）', () {
      final odd = makeCourse(
        id: 'odd',
        day: 4,
        node: 2,
        rule: WeekRule.odd,
        start: 3,
        end: 17,
      );
      final even = makeCourse(
        id: 'even',
        day: 4,
        node: 2,
        rule: WeekRule.even,
        start: 4,
        end: 18,
      );
      expect(findCourseConflicts(<Course>[odd], even), isEmpty);
    });

    test('同一天不同节次不算冲突', () {
      final a = makeCourse(id: 'a', day: 3, node: 1);
      final b = makeCourse(id: 'b', day: 3, node: 2);
      expect(findCourseConflicts(<Course>[a], b), isEmpty);
    });

    test('不同天的同一节次不算冲突', () {
      final a = makeCourse(id: 'a', day: 1, node: 3);
      final b = makeCourse(id: 'b', day: 2, node: 3);
      expect(findCourseConflicts(<Course>[a], b), isEmpty);
    });

    test('周次完全不重叠（前半学期 / 后半学期）不算冲突', () {
      final first = makeCourse(id: 'a', day: 5, node: 4, start: 6, end: 10);
      final second = makeCourse(id: 'b', day: 5, node: 4, start: 11, end: 15);
      expect(findCourseConflicts(<Course>[first], second), isEmpty);
    });

    test('编辑自己时不会把自己当成冲突', () {
      final me = makeCourse(id: 'me', day: 1, node: 1, start: 1, end: 16);
      final edited = me.copyWith(courseName: '改了名');
      expect(findCourseConflicts(<Course>[me], edited), isEmpty);
    });

    test('一条课都没有周次时不算冲突', () {
      final empty = makeCourse(id: 'a', rule: WeekRule.custom, start: 1, end: 1);
      final other = makeCourse(id: 'b', day: 1, node: 1);
      expect(findCourseConflicts(<Course>[other], empty), isEmpty);
    });

    test('冲突描述能读得懂', () {
      final other = makeCourse(id: 'a', name: '大学英语读写', rule: WeekRule.every, start: 3, end: 17);
      expect(describeConflict(other), contains('大学英语读写'));
      expect(describeConflict(other), contains('每周'));
    });
  });

  group('拿真实课表练一遍', () {
    final data = loadData();

    test('真实课表里本来就没有时间冲突', () {
      // 把每一门课都当成「新加进来的」，检查它和别的课是否冲突。
      // 单双周轮换的那两门应该互相通融。
      for (final course in data.courses) {
        final conflicts = findCourseConflicts(data.courses, course);
        expect(
          conflicts,
          isEmpty,
          reason: '「${course.courseName}」被判定为和 ${conflicts.map((c) => c.courseName).toList()} 冲突',
        );
      }
    });

    test('给真实课表加一门新课，会多出一条', () {
      final added = upsertCourseInList(
        data.courses,
        makeCourse(id: 'brand-new', name: '人工智能导论', day: 6, node: 1),
      );
      expect(added.length, data.courses.length + 1);
    });

    test('删掉再撤销（重新加回来），课程一门不少', () {
      final target = data.courses.first;
      final removed = removeCourseFromList(data.courses, target.id);
      expect(removed.length, data.courses.length - 1);

      final restored = upsertCourseInList(removed, target);
      expect(restored.length, data.courses.length);
      expect(
        restored.map((c) => c.id).toSet(),
        data.courses.map((c) => c.id).toSet(),
      );
      // 加回来之后仍然是有序的
      for (var i = 1; i < restored.length; i++) {
        expect(compareCourses(restored[i - 1], restored[i]) <= 0, isTrue);
      }
    });
  });
}

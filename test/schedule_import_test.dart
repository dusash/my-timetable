// 导入时的「重编号」和「去重合并」的自动化测试。
//
// 同学发来的课表里，课程 id 是他手机上的编号（i1、i2…）。
// 如果直接搬进来，很可能和你自己的 c1、c2 撞车 —— 撞车的后果是
// 「改一门课，另一门跟着变」。所以外来课程一律重新发号；
// 同时导入两次不能变成双份。这两件事都在这里守住。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/logic/schedule_editor.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';
import 'package:my_timetable/state/schedule_controller.dart';

ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

Course makeCourse({
  required String id,
  String name = '测试课',
  int day = 1,
  int node = 1,
  WeekRule rule = WeekRule.every,
  int start = 1,
  int end = 16,
  List<int> custom = const <int>[],
}) {
  return Course(
    id: id,
    courseName: name,
    teacher: '',
    courseCode: '',
    dayOfWeek: day,
    node: node,
    weekRule: rule,
    startWeek: start,
    endWeek: end,
    customWeeks: custom,
  );
}

void main() {
  group('重新发号', () {
    test('外来课程的 id 全部被换掉，而且互不重复', () {
      final incoming = loadData().courses;
      final renumbered = renumberCourses(incoming);

      final ids = renumbered.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: '不能有重复 id');
      for (final original in incoming) {
        expect(ids.contains(original.id), isFalse);
      }
    });

    test('课程内容不变，只是换了号', () {
      final incoming = loadData().courses;
      final renumbered = renumberCourses(incoming);

      expect(renumbered.length, incoming.length);
      // renumberCourses 会排序，所以按「星期+节次」对齐着比
      final a = <Course>[...incoming]..sort(compareCourses);
      for (var i = 0; i < a.length; i++) {
        expect(renumbered[i].courseName, a[i].courseName);
        expect(renumbered[i].dayOfWeek, a[i].dayOfWeek);
        expect(renumbered[i].node, a[i].node);
      }
    });

    test('重编号的结果本身也是排好序的', () {
      final renumbered = renumberCourses(loadData().courses);
      for (var i = 1; i < renumbered.length; i++) {
        expect(compareCourses(renumbered[i - 1], renumbered[i]), lessThan(0));
      }
    });
  });

  group('判重规则', () {
    test('排课信息完全一样的算同一节课', () {
      final a = makeCourse(id: 'a', name: '高等数学', day: 1, node: 1);
      final b = makeCourse(id: 'b', name: '高等数学', day: 1, node: 1);
      expect(isSameArrangement(a, b), isTrue);
    });

    test('课名不同就不算重复', () {
      final a = makeCourse(id: 'a', name: '高等数学');
      final b = makeCourse(id: 'b', name: '大学物理');
      expect(isSameArrangement(a, b), isFalse);
    });

    test('同一格但单双周不同，是两门不同的课', () {
      final a = makeCourse(id: 'a', name: '英语', day: 4, node: 2, rule: WeekRule.odd);
      final b = makeCourse(id: 'b', name: '英语', day: 4, node: 2, rule: WeekRule.even);
      expect(isSameArrangement(a, b), isFalse);
    });

    test('自定义周次只看集合，不看顺序', () {
      final a = makeCourse(
        id: 'a',
        name: '形势与政策',
        rule: WeekRule.custom,
        custom: <int>[1, 3, 5],
      );
      final b = makeCourse(
        id: 'b',
        name: '形势与政策',
        rule: WeekRule.custom,
        custom: <int>[5, 1, 3],
      );
      expect(isSameArrangement(a, b), isTrue);
    });

    test('教师和教室不同仍然算重复（宁可多留也不要漏）', () {
      final a = makeCourse(id: 'a', name: '高等数学');
      final b = Course(
        id: 'b',
        courseName: '高等数学',
        teacher: '张三',
        courseCode: '',
        dayOfWeek: 1,
        node: 1,
        weekRule: WeekRule.every,
        startWeek: 1,
        endWeek: 16,
        classroom: '教5-201',
      );
      expect(isSameArrangement(a, b), isTrue);
    });
  });

  group('合并进现有课表', () {
    test('把自己那份合并进来，应该一条都不新增', () {
      final mine = loadData().courses;
      final result = mergeCoursesIntoList(mine, mine);

      expect(result.added, 0);
      expect(result.skipped, mine.length);
      expect(result.courses.length, mine.length);
    });

    test('导入全新的一门课，数量正好加一', () {
      final mine = loadData().courses;
      final fresh = makeCourse(id: 'x', name: '人工智能导论', day: 5, node: 3);

      final result = mergeCoursesIntoList(mine, <Course>[fresh]);

      expect(result.added, 1);
      expect(result.skipped, 0);
      expect(result.courses.length, mine.length + 1);
      expect(
        result.courses.any((c) => c.courseName == '人工智能导论'),
        isTrue,
      );
    });

    test('同一份导入两次，第二次一条都不加', () {
      final mine = loadData().courses;
      final incoming = <Course>[
        makeCourse(id: 'x', name: '人工智能导论', day: 5, node: 3),
      ];

      final first = mergeCoursesIntoList(mine, incoming);
      final second = mergeCoursesIntoList(first.courses, incoming);

      expect(first.added, 1);
      expect(second.added, 0);
      expect(second.skipped, 1);
    });

    test('合并后 id 不会撞车', () {
      final mine = loadData().courses;
      final result = mergeCoursesIntoList(mine, mine);

      final ids = result.courses.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('通过控制器导入', () {
    Future<ScheduleController> freshController() async {
      final controller = ScheduleController(
        repository: ScheduleRepository(
          store: MemoryScheduleStore(),
          seedJson: File('assets/data/sample_schedule.json').readAsStringSync(),
        ),
      );
      await controller.load();
      return controller;
    }

    test('合并导入：只补缺的，保留自己的学期设置', () async {
      final controller = await freshController();
      final before = controller.data!.courses.length;
      final mySemester = controller.data!.semester.name;

      final incoming = loadData().copyWith(
        semester: loadData().semester,
        courses: <Course>[
          ...loadData().courses,
          makeCourse(id: 'x', name: '人工智能导论', day: 5, node: 3),
        ],
      );

      final result = await controller.importMerge(incoming);

      expect(result.added, 1);
      expect(result.skipped, loadData().courses.length);
      expect(controller.data!.courses.length, before + 1);
      expect(controller.data!.semester.name, mySemester, reason: '学期设置不该被换掉');
    });

    test('合并导入会落盘', () async {
      final controller = await freshController();
      await controller.importMerge(
        loadData().copyWith(
          courses: <Course>[makeCourse(id: 'x', name: '人工智能导论', day: 5, node: 3)],
        ),
      );

      final reloaded = await controller.repository.load();
      expect(
        reloaded.courses.any((c) => c.courseName == '人工智能导论'),
        isTrue,
      );
    });

    test('整份替换会清掉原来的课', () async {
      final controller = await freshController();
      expect(controller.data!.courses.length, 16);

      final incoming = loadData().copyWith(
        semester: Semester(
          name: '同学的学期',
          week1Start: loadData().semester.week1Start,
          totalWeeks: loadData().semester.totalWeeks,
        ),
        courses: <Course>[makeCourse(id: 'x', name: '唯一一门课', day: 3, node: 2)],
      );

      await controller.importReplaceAll(incoming);

      expect(controller.data!.courses.length, 1);
      expect(controller.data!.courses.single.courseName, '唯一一门课');
      expect(controller.data!.semester.name, '同学的学期');

      final reloaded = await controller.repository.load();
      expect(reloaded.courses.length, 1);
    });

    test('空课表上合并 = 直接照单全收', () async {
      final controller = ScheduleController(
        repository: ScheduleRepository(store: MemoryScheduleStore()),
      );
      await controller.load();
      expect(controller.data!.courses, isEmpty);

      final result = await controller.importMerge(loadData());

      expect(result.added, loadData().courses.length);
      expect(controller.data!.courses.length, loadData().courses.length);
      expect(controller.data!.periods, isNotEmpty, reason: '作息时间也该一起收下');
    });
  });
}

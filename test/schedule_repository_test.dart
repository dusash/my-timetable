// 阶段 3「本地保存」的自动化测试。
//
// 用的是 MemoryScheduleStore（只放内存），所以测试不会碰你手机、也不会留垃圾文件，
// 但验证的是同一套 ScheduleRepository 代码。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/models/class_period.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';

String seedText() => File('assets/data/sample_schedule.json').readAsStringSync();

void main() {
  group('ScheduleStore 本身', () {
    test('没存过的时候读出来是 null', () async {
      final store = MemoryScheduleStore();
      expect(await store.read(), isNull);
    });

    test('写进去能读出来', () async {
      final store = MemoryScheduleStore();
      await store.write('你好');
      expect(await store.read(), '你好');
    });

    test('再写一次会覆盖', () async {
      final store = MemoryScheduleStore('旧的');
      await store.write('新的');
      expect(await store.read(), '新的');
    });

    test('clear 之后又变回没存过的样子', () async {
      final store = MemoryScheduleStore('内容');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('第一次打开 App', () {
    test('没有存档时用出厂数据，并且顺手存下来', () async {
      final store = MemoryScheduleStore();
      final repo = ScheduleRepository(store: store, seedJson: seedText());

      final data = await repo.load();

      expect(data.courses.length, 16);
      expect(await store.read(), isNotNull, reason: '出厂数据应该被保存，下次就不用再解析');
    });

    test('连出厂数据都没有时，给一份空课表而不是崩掉', () async {
      final repo = ScheduleRepository(store: MemoryScheduleStore());
      final data = await repo.load();

      expect(data.courses, isEmpty);
      expect(data.semester.totalWeeks, greaterThan(0));
    });
  });

  group('第二次打开 App', () {
    test('优先用本机保存的那份，出厂数据不再覆盖它', () async {
      final store = MemoryScheduleStore();
      final repo = ScheduleRepository(store: store, seedJson: seedText());

      // 第一次：铺上出厂数据
      final first = await repo.load();
      expect(first.courses.length, 16);

      // 用户删了两门课并保存
      final edited = first.copyWith(
        courses: first.courses.take(14).toList(),
      );
      await repo.save(edited);

      // 第二次打开：应该看到 14 门
      final second = await repo.load();
      expect(second.courses.length, 14);
    });

    test('存档坏掉时给一份空课表，App 不会打不开', () async {
      final store = MemoryScheduleStore('这不是 JSON，只是一段乱码 {{{');
      final repo = ScheduleRepository(store: store, seedJson: seedText());

      final data = await repo.load();

      expect(data.courses, isEmpty);
      // 关键：坏掉的存档要原样留着别覆盖 —— 万一还能手工抢救回来，
      // 一覆盖就彻底没证据了。
      expect(await store.read(), '这不是 JSON，只是一段乱码 {{{');
    });

    test('存档是空字符串时也当没存过', () async {
      final store = MemoryScheduleStore('   ');
      final repo = ScheduleRepository(store: store, seedJson: seedText());

      final data = await repo.load();
      expect(data.courses.length, 16);
    });

    test('没有内置数据时，第一次打开拿到的是空课表（但带默认作息）', () async {
      final store = MemoryScheduleStore();
      // 正式 App 就是这个样子：不传 seed。
      final repo = ScheduleRepository(store: store);

      final data = await repo.load();

      expect(data.courses, isEmpty, reason: '出厂必须是干净的，一门课都不预装');
      expect(data.periods, isNotEmpty, reason: '空课表也得有作息，否则用户连第几节都选不了');
      expect(
        await store.read(),
        isNotNull,
        reason: '要顺手存下来，否则开学日期会每次启动都跟着今天跑',
      );
    });
  });

  group('存进去再读出来，内容一点都不能变', () {
    test('课程、作息、学期信息全都原样保留', () async {
      final store = MemoryScheduleStore();
      final repo = ScheduleRepository(store: store);

      final original = ScheduleData(
        campus: '示例大学',
        semester: Semester(
          name: '2026-2027 秋季学期',
          week1Start: DateTime(2026, 9, 7),
          totalWeeks: 20,
        ),
        periods: const <ClassPeriod>[
          ClassPeriod(node: 1, label: '第一节', start: '08:00', end: '09:35'),
          ClassPeriod(node: 2, label: '第二节', start: '10:05', end: '11:40'),
        ],
        courses: <Course>[
          Course(
            id: 'x1',
            courseName: '大学英语读写（1）',
            teacher: '李老师',
            courseCode: 'ENG001',
            dayOfWeek: 4,
            node: 2,
            weekRule: WeekRule.odd,
            startWeek: 3,
            endWeek: 17,
            classroom: '外语楼102',
            overrides: const <int, bool>{7: false, 9: true},
          ),
        ],
      );

      await repo.save(original);
      final loaded = await repo.load();

      expect(loaded.campus, original.campus);
      expect(loaded.semester.name, original.semester.name);
      expect(loaded.semester.week1Start, original.semester.week1Start);
      expect(loaded.semester.totalWeeks, original.semester.totalWeeks);
      expect(loaded.periods.length, 2);
      expect(loaded.periods[1].start, '10:05');

      final c = loaded.courses.single;
      expect(c.id, 'x1');
      expect(c.courseName, '大学英语读写（1）');
      expect(c.teacher, '李老师');
      expect(c.courseCode, 'ENG001');
      expect(c.dayOfWeek, 4);
      expect(c.node, 2);
      expect(c.weekRule, WeekRule.odd);
      expect(c.startWeek, 3);
      expect(c.endWeek, 17);
      expect(c.classroom, '外语楼102');
      expect(c.overrides, <int, bool>{7: false, 9: true});
      // 展开出来的周次也要一致
      expect(loaded.courses.single.weeks, original.courses.single.weeks);
    });
  });

  group('恢复出厂', () {
    test('resetToDefault 会把本机的改动清掉', () async {
      final store = MemoryScheduleStore();
      final repo = ScheduleRepository(store: store, seedJson: seedText());

      final first = await repo.load();
      await repo.save(first.copyWith(courses: <Course>[]));
      expect((await repo.load()).courses, isEmpty);

      final reset = await repo.resetToDefault();
      expect(reset.courses.length, 16);
      expect((await repo.load()).courses.length, 16);
    });
  });
}

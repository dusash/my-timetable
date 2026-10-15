// 教务系统文本导入的自动化测试。
//
// 教务系统的导出格式五花八门，所以这个解析器的策略是「宽容」：
// 一行一门课、一门课占好几行、带不带教师、单双周写成什么样子，
// 都要尽量认出来。这里把常见的几种写法都固定下来，
// 以后改解析规则时能立刻知道有没有弄坏旧格式。

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/logic/schedule_parser.dart';
import 'package:my_timetable/models/course.dart';

/// 在结果里找「星期 [day] 的第 [node] 节」那一条。
Course? at(ParseResult result, int day, int node) {
  for (final c in result.courses) {
    if (c.dayOfWeek == day && c.node == node) return c;
  }
  return null;
}

void main() {
  group('一行一门课的格式', () {
    const text = '''
高等数学B（上） 周一 第1-2节 3-15周 教5-201 张三
大学英语读写（1） 周四 第2节 3-17周(单) 东12-301 李四
大学英语视听说（1） 周四 第2节 4-18周(双) 东12-301 李四
''';

    test('连堂会被拆成两条安排', () {
      final result = parseScheduleText(text);
      expect(at(result, 1, 1), isNotNull);
      expect(at(result, 1, 2), isNotNull);
      expect(at(result, 1, 3), isNull, reason: '第 1-2 节不该多出第 3 节');
    });

    test('课名、教室、教师都认得出来', () {
      final result = parseScheduleText(text);
      final course = at(result, 1, 1)!;

      expect(course.courseName, '高等数学B（上）');
      expect(course.teacher, '张三');
      expect(course.classroom, '教5-201');
      expect(course.weekRule, WeekRule.every);
      expect(course.startWeek, 3);
      expect(course.endWeek, 15);
    });

    test('半角括号的「(单)」「(双)」能识别', () {
      final result = parseScheduleText(text);

      final odd = at(result, 4, 2);
      expect(odd, isNotNull);
      expect(odd!.weekRule, WeekRule.odd);
      // 单双周是同一格的两门课，课名要能分开
      final names = result.courses
          .where((c) => c.dayOfWeek == 4 && c.node == 2)
          .map((c) => c.courseName)
          .toSet();
      expect(names, containsAll(<String>['大学英语读写（1）', '大学英语视听说（1）']));
    });

    test('同一天的第二节既有单周课又有双周课', () {
      final result = parseScheduleText(text);
      final thursday2 = result.courses
          .where((c) => c.dayOfWeek == 4 && c.node == 2)
          .toList();

      expect(thursday2.length, 2);
      expect(
        thursday2.map((c) => c.weekRule).toSet(),
        <WeekRule>{WeekRule.odd, WeekRule.even},
      );
    });
  });

  group('一门课占好几行的格式', () {
    const text = '''
星期一
第1-2节
高等数学B（上）
教5-201
张三
3-15周

星期二
第3节
大学物理
东12-301
王五
1-16周
''';

    test('按「星期X」把多行聚成一门课', () {
      final result = parseScheduleText(text);

      expect(result.courses.length, 3, reason: '高等数学 2 节 + 大学物理 1 节');
      expect(at(result, 1, 1)!.courseName, '高等数学B（上）');
      expect(at(result, 2, 3)!.courseName, '大学物理');
    });

    test('跨行也能认出教室和周次', () {
      final result = parseScheduleText(text);
      final physics = at(result, 2, 3)!;

      expect(physics.classroom, '东12-301');
      expect(physics.startWeek, 1);
      expect(physics.endWeek, 16);
    });
  });

  group('各种周次写法', () {
    test('「1-16周」是每周都上', () {
      final result = parseScheduleText('体育 周三 第5节 1-16周 田径场 王五');
      expect(result.courses.single.weekRule, WeekRule.every);
      expect(result.courses.single.startWeek, 1);
      expect(result.courses.single.endWeek, 16);
    });

    test('「1,3,5,7周」当成自定义周次', () {
      final result = parseScheduleText('形势与政策 周五 第4节 1,3,5,7周 东12-301 赵六');
      final course = result.courses.single;

      expect(course.weekRule, WeekRule.custom);
      expect(course.customWeeks, <int>[1, 3, 5, 7]);
      expect(course.weeks, <int>[1, 3, 5, 7]);
    });

    test('只写「第5周」就是只上这一周', () {
      final result = parseScheduleText('讲座 周五 第4节 第5周 报告厅 钱七');
      expect(result.courses.single.startWeek, 5);
      expect(result.courses.single.endWeek, 5);
    });

    test('全角括号的「（单）」也能认', () {
      final result = parseScheduleText('毛概 周二 第1节 3-15周（单） 东1-101 孙八');
      expect(result.courses.single.weekRule, WeekRule.odd);
    });

    test('「单周」两个字也能认', () {
      final result = parseScheduleText('毛概 周二 第1节 3-15周单周 东1-101 孙八');
      expect(result.courses.single.weekRule, WeekRule.odd);
    });

    test('完全没写周次时，按整学期兜底', () {
      final result = parseScheduleText(
        '自习 周日 第1节 图书馆',
        defaultTotalWeeks: 18,
      );
      final course = result.courses.single;
      expect(course.startWeek, 1);
      expect(course.endWeek, 18);
    });
  });

  group('认不出来的时候', () {
    test('空文本给空结果', () {
      final result = parseScheduleText('   \n\n  ');
      expect(result.isEmpty, isTrue);
      expect(result.lineCount, 0);
    });

    test('没有星期的文字会进「没认出来」清单，而不是被静默丢掉', () {
      final result = parseScheduleText('''
这是一段和课表无关的话
高等数学 周一 第1节 1-16周 教5-201
''');

      expect(result.courses.length, 1);
      expect(result.unrecognized.length, 1);
      expect(result.unrecognized.first, contains('无关'));
    });

    test('有星期但没有节次，也算没认出来', () {
      final result = parseScheduleText('高等数学 周一 图书馆自习');
      expect(result.isEmpty, isTrue);
      expect(result.unrecognized.length, 1);
    });

    test('纯数字的表格噪音不会当成错误提示出来', () {
      final result = parseScheduleText('''
2026
1 2 3
高等数学 周一 第1节 1-16周
''');
      expect(result.courses.length, 1);
      expect(result.unrecognized, isEmpty);
    });
  });

  group('统计信息', () {
    test('courseNameCount 数的是「几门课」而不是「几条安排」', () {
      final result = parseScheduleText('''
高等数学B（上） 周一 第1-2节 3-15周 教5-201 张三
大学物理 周二 第3节 1-16周 东12-301 王五
''');
      expect(result.courses.length, 3, reason: '高等数学占了 2 节');
      expect(result.courseNameCount, 2);
    });

    test('lineCount 是读进来的有效行数', () {
      final result = parseScheduleText('高等数学 周一 第1节\n\n大学物理 周二 第2节\n');
      expect(result.lineCount, 2);
    });
  });
}

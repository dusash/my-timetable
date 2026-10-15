// 内置示例课表的测试。
//
// 示例课表是开源出去之后别人第一眼会碰到的东西，所以两件事必须钉死：
//   1. 里面**不能**混进任何真实信息（老师姓名、真实教室、真实学校）；
//   2. 开学日期要校正，免得过几个月再点开就变成一片空白。

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/sample_schedule.dart';

void main() {
  // 读 rootBundle 需要先把测试绑定初始化好。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内置示例课表', () {
    test('读得出来，而且确实有课、有作息', () async {
      final sample = await loadSampleSchedule();

      expect(sample, isNotNull, reason: 'assets 里没找到示例课表');
      expect(sample!.courses, isNotEmpty);
      expect(sample.periods, isNotEmpty, reason: '没有作息就画不出时间列');
    });

    test('示例要能展示全部玩法：单周、双周、连堂、短期课都有', () async {
      final sample = (await loadSampleSchedule())!;
      final rules = sample.courses.map((c) => c.weekRule).toSet();

      expect(rules.length, greaterThanOrEqualTo(3), reason: '至少有每周 / 单周 / 双周三种');
      // 单双周成对出现，才看得出「同一格两周换着上」的效果
      expect(
        sample.courses.any((c) => c.weekRule.code == 'ODD'),
        isTrue,
      );
      expect(
        sample.courses.any((c) => c.weekRule.code == 'EVEN'),
        isTrue,
      );
      // 同一星期、节次相邻的两条 → 会被合并成一张跨行的卡（连堂）
      final slots = sample.courses
          .map((c) => '${c.dayOfWeek}-${c.node}')
          .toSet();
      expect(
        sample.courses.any((c) => slots.contains('${c.dayOfWeek}-${c.node + 1}')),
        isTrue,
        reason: '要有一组连堂课，才能演示跨行合并的卡片',
      );
      // 只上几周的短期课（形势与政策那种）
      expect(
        sample.courses.any((c) => c.endWeek - c.startWeek <= 5),
        isTrue,
        reason: '要有一门只上几周的课，才能演示「本周不上」的灰色卡',
      );
    });

    test('不含任何真实个人信息：老师、教室、学校都是编的', () async {
      final sample = (await loadSampleSchedule())!;

      expect(sample.campus, '示例大学');

      // 这几个名字是改造前真实数据里的老师，只要再出现就说明又混进真数据了
      const realTeachers = <String>[
        '吴海涛',
        '盛成林',
        '张燕D',
        '冯强',
        '漆江',
        '陈红莲C2',
        '姜邵瑾',
        '陈泽炜',
        '艾思琦',
      ];
      final teachers = sample.courses.map((c) => c.teacher).toSet();
      for (final name in realTeachers) {
        expect(
          teachers,
          isNot(contains(name)),
          reason: '示例数据里出现了真实教师「$name」',
        );
      }

      // 真实教室也不该出现
      final rooms = sample.courses.map((c) => c.classroom).join(' ');
      expect(rooms, isNot(contains('西5-')));
      expect(rooms, isNot(contains('西6-')));
      expect(rooms, isNot(contains('西2-')));
      expect(rooms, isNot(contains('西7-')));
    });

    test('开学日期会校正：不管哪天打开，都停在开学的第 6 周', () async {
      // 挑一个和示例文件里写的日期完全无关的「今天」
      final today = DateTime(2027, 3, 17); // 星期三
      final sample = (await loadSampleSchedule(now: today))!;

      expect(
        sample.semester.weekOf(today),
        6,
        reason: '示例要固定停在第 6 周，那一周各种课都上着，不会是一片空',
      );
      expect(
        sample.semester.week1Start.weekday,
        DateTime.monday,
        reason: '第 1 周的第 1 天必须是周一，否则整学期周次会错位',
      );
    });

    test('同一天反复读，结果一致（不依赖当前时刻的时分秒）', () async {
      final a = await loadSampleSchedule(now: DateTime(2027, 3, 17, 1, 30));
      final b = await loadSampleSchedule(now: DateTime(2027, 3, 17, 23, 50));

      expect(a!.semester.week1Start, b!.semester.week1Start);
    });
  });
}

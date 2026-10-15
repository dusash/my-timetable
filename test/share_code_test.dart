// 分享码的自动化测试。
//
// 分享码是这个 App 里唯一「跨设备传数据」的通道，一旦编解码不对称，
// 同学导入进来的课表就会缺胳膊少腿，而且很难发现（看起来像导入成功了）。
// 所以这里把「编一次 → 解一次，所有字段逐个比对」当成最重要的用例。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/logic/share_code.dart';
import 'package:my_timetable/models/course.dart';

ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

/// 手工拼一个「高版本」的分享码，用来测版本兼容提示。
String makeCode(Map<String, dynamic> compact) {
  final packed = gzip.encode(utf8.encode(jsonEncode(compact)));
  return '$kShareCodePrefix:${base64Url.encode(packed).replaceAll('=', '')}';
}

/// 逐个字段比一门课，比 toString 更能指出到底哪一项对不上。
void expectSameCourse(Course a, Course b) {
  expect(b.courseName, a.courseName, reason: '课名');
  expect(b.teacher, a.teacher, reason: '教师');
  expect(b.courseCode, a.courseCode, reason: '课程代码');
  expect(b.dayOfWeek, a.dayOfWeek, reason: '星期');
  expect(b.node, a.node, reason: '节次');
  expect(b.weekRule, a.weekRule, reason: '周次规则');
  expect(b.startWeek, a.startWeek, reason: '起始周');
  expect(b.endWeek, a.endWeek, reason: '结束周');
  expect(b.customWeeks, a.customWeeks, reason: '自定义周次');
  expect(b.classroom, a.classroom, reason: '教室');
  expect(b.overrides, a.overrides, reason: '调休设置');
}

void main() {
  group('编码与解码', () {
    test('分享码以 KTB1: 开头', () {
      final code = ShareCode.encode(loadData());
      expect(code.startsWith('$kShareCodePrefix:'), isTrue);
    });

    test('编一次再解一次，课表内容一字不差', () {
      final original = loadData();
      final restored = ShareCode.decode(ShareCode.encode(original));

      expect(restored.campus, original.campus);
      expect(restored.semester.name, original.semester.name);
      expect(restored.semester.week1Start, original.semester.week1Start);
      expect(restored.semester.totalWeeks, original.semester.totalWeeks);

      expect(restored.periods.length, original.periods.length);
      for (var i = 0; i < original.periods.length; i++) {
        expect(restored.periods[i].node, original.periods[i].node);
        expect(restored.periods[i].start, original.periods[i].start);
        expect(restored.periods[i].end, original.periods[i].end);
      }

      expect(restored.courses.length, original.courses.length);
      for (var i = 0; i < original.courses.length; i++) {
        expectSameCourse(original.courses[i], restored.courses[i]);
      }
    });

    test('分享码比原始 JSON 短很多（压缩真的生效了）', () {
      final data = loadData();
      final raw = data.toJsonString();
      final code = ShareCode.encode(data);

      expect(code.length, lessThan(raw.length / 2));
    });

    test('分享码里不带课程 id（避免和同学手机上的编号撞车）', () {
      final data = loadData();
      final restored = ShareCode.decode(ShareCode.encode(data));

      for (final course in restored.courses) {
        expect(course.id.startsWith('shared'), isTrue);
      }
      // 原来的 id（c1、c2 …）一个都不该出现
      final originalIds = data.courses.map((c) => c.id).toSet();
      for (final course in restored.courses) {
        expect(originalIds.contains(course.id), isFalse);
      }
    });

    test('调休设置会跟着一起传过去', () {
      final data = loadData();
      final withOverride = data.copyWith(
        courses: <Course>[
          data.courses.first.copyWith(overrides: const <int, bool>{5: false, 7: true}),
          ...data.courses.skip(1),
        ],
      );

      final restored = ShareCode.decode(ShareCode.encode(withOverride));
      expect(restored.courses.first.overrides, <int, bool>{5: false, 7: true});
    });

    test('空课表也能编能解', () {
      final empty = ScheduleData.empty(
        campus: '测试校区',
        semesterName: '空学期',
        week1Start: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      final restored = ShareCode.decode(ShareCode.encode(empty));

      expect(restored.courses, isEmpty);
      expect(restored.campus, '测试校区');
      expect(restored.semester.totalWeeks, 18);
    });
  });

  group('复制粘贴带来的小毛病都能忍', () {
    test('前后多出空格和换行', () {
      final code = ShareCode.encode(loadData());
      expect(
        ShareCode.decode('   \n  $code  \n\n ').courses.length,
        loadData().courses.length,
      );
    });

    test('中间被自动换行打断', () {
      final code = ShareCode.encode(loadData());
      final broken = StringBuffer();
      for (var i = 0; i < code.length; i += 40) {
        broken.write(code.substring(i, (i + 40).clamp(0, code.length)));
        broken.write('\n');
      }
      expect(
        ShareCode.decode(broken.toString()).courses.length,
        loadData().courses.length,
      );
    });

    test('前面带着「我给你我的课表：」这类说明文字', () {
      final code = ShareCode.encode(loadData());
      final decoded = ShareCode.decode('我的课表给你：\n$code\n收到回我一下');
      expect(decoded.courses.length, loadData().courses.length);
    });

    test('前缀后面是全角冒号', () {
      final code = ShareCode.encode(loadData());
      final weird = code.replaceFirst('$kShareCodePrefix:', '$kShareCodePrefix：');
      expect(decodedCount(weird), loadData().courses.length);
    });
  });

  group('认不出来的时候说人话', () {
    test('什么都没粘', () {
      expect(
        () => ShareCode.decode('   '),
        throwsA(
          isA<ShareCodeException>().having(
            (e) => e.message,
            'message',
            contains('还没有粘贴'),
          ),
        ),
      );
    });

    test('粘的是别人随便发的一段话', () {
      expect(
        () => ShareCode.decode('今天中午吃什么'),
        throwsA(isA<ShareCodeException>()),
      );
    });

    test('分享码被截断了', () {
      final code = ShareCode.encode(loadData());
      final half = code.substring(0, code.length ~/ 2);
      expect(
        () => ShareCode.decode(half),
        throwsA(
          isA<ShareCodeException>().having(
            (e) => e.message,
            'message',
            contains('重新发'),
          ),
        ),
      );
    });

    test('版本比本机新时提示升级', () {
      final future = makeCode(<String, dynamic>{
        'v': kShareCodeVersion + 1,
        'c': '',
        's': <dynamic>['未来学期', '2027-03-01', 20],
        'p': <dynamic>[],
        'k': <dynamic>[
          <dynamic>['未来课', '', '', 1, 1, 'EVERY', 1, 20, <int>[], '', <String, bool>{}],
        ],
      });
      expect(
        () => ShareCode.decode(future),
        throwsA(
          isA<ShareCodeException>().having(
            (e) => e.message,
            'message',
            contains('升级'),
          ),
        ),
      );
    });

    test('空课表的分享码能正常解开，只是里面没有课', () {
      final hollow = makeCode(<String, dynamic>{
        'v': kShareCodeVersion,
        'c': '',
        's': <dynamic>['空的', '2026-09-07', 20],
        'p': <dynamic>[],
        'k': <dynamic>[],
      });
      final data = ShareCode.decode(hollow);

      expect(data.courses, isEmpty);
      expect(data.periods, isEmpty);
    });

    test('是压缩过的 JSON，但不是课表（别的 App 的码）会被拒绝', () {
      final alien = makeCode(<String, dynamic>{
        'hello': 'world',
        'list': <int>[1, 2, 3],
      });
      expect(
        () => ShareCode.decode(alien),
        throwsA(
          isA<ShareCodeException>().having(
            (e) => e.message,
            'message',
            contains('不是一份课表分享码'),
          ),
        ),
      );
    });
  });

  group('二维码容量判断', () {
    test('正常课表能画成二维码', () {
      final code = ShareCode.encode(loadData());
      expect(ShareCode.fitsInQrCode(code), isTrue);
      expect(ShareCode.payloadLength(code), lessThan(kMaxQrPayloadLength));
    });

    test('特别大的课表会判定成放不下', () {
      final courses = <Course>[
        for (var i = 0; i < 400; i++)
          Course(
            id: 'big$i',
            courseName: '一门名字很长很长的课程名称第$i号',
            teacher: '某位老师',
            courseCode: 'CODE$i',
            dayOfWeek: i % 7 + 1,
            node: i % 12 + 1,
            weekRule: WeekRule.every,
            startWeek: 1,
            endWeek: 20,
            classroom: '教5-201',
          ),
      ];
      final huge = ScheduleData(
        campus: '某大学',
        semester: loadData().semester,
        periods: loadData().periods,
        courses: courses,
      );

      expect(ShareCode.fitsInQrCode(ShareCode.encode(huge)), isFalse);
    });
  });
}

/// 只关心「解开之后有几条课」时的顺手写法。
int decodedCount(String code) => ShareCode.decode(code).courses.length;

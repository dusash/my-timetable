import 'dart:convert';

import '../models/class_period.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../logic/week_calculator.dart';

/// 空课表自带的默认作息：上午 4 节 + 下午 4 节 + 晚上 2 节。
///
/// 为什么「空的课表」也必须有作息：
///   · 课表网格左侧那一列要显示每节的起止时间，没有作息就是一片空白；
///   · 用户录课时得从「第几节」里选，没有作息连选项都没有。
/// 所以它是一份**骨架**，不是数据 —— 用户随时可以在设置页里增删改。
/// 这套时间是比较通用的大学作息，绝大多数学校改一两处就能用。
const List<ClassPeriod> kDefaultPeriods = <ClassPeriod>[
  ClassPeriod(node: 1, label: '第一节', start: '08:00', end: '08:45'),
  ClassPeriod(node: 2, label: '第二节', start: '08:55', end: '09:40'),
  ClassPeriod(node: 3, label: '第三节', start: '10:00', end: '10:45'),
  ClassPeriod(node: 4, label: '第四节', start: '10:55', end: '11:40'),
  ClassPeriod(node: 5, label: '第五节', start: '14:00', end: '14:45'),
  ClassPeriod(node: 6, label: '第六节', start: '14:55', end: '15:40'),
  ClassPeriod(node: 7, label: '第七节', start: '16:00', end: '16:45'),
  ClassPeriod(node: 8, label: '第八节', start: '16:55', end: '17:40'),
  ClassPeriod(node: 9, label: '第九节', start: '19:00', end: '19:45'),
  ClassPeriod(node: 10, label: '第十节', start: '19:55', end: '20:40'),
];

/// 某一天所在那一周的周一（只保留日期，去掉时分秒）。
DateTime mondayOfDate(DateTime date) {
  final day = Semester.dateOnly(date);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 一份完整课表 = 学期信息 + 作息时间 + 所有上课安排。
///
/// 这个类刻意不认识「文件」和「网络」：它只负责把一段 JSON 文本变成对象。
/// 这样以后不管是读内置资源、读本地数据库，还是读同学分享过来的文件，
/// 用的都是同一套解析代码。
class ScheduleData {
  /// 校区 / 学校名，仅用于显示。
  final String campus;

  /// 学期信息。
  final Semester semester;

  /// 作息时间表。
  final List<ClassPeriod> periods;

  /// 所有上课安排。
  final List<Course> courses;

  const ScheduleData({
    required this.campus,
    required this.semester,
    required this.periods,
    required this.courses,
  });

  /// 新建一份空课表：**一套默认作息 + 零门课**。
  ///
  /// 这是 App 出厂时的样子 —— 干净、不含任何别人的数据，用户自己往里录。
  /// 开学日期默认取「今天所在那一周的周一」，这样装完打开就是第 1 周，
  /// 不会因为今天恰好是周三而把整学期周次算歪。
  factory ScheduleData.empty({
    String campus = '',
    String semesterName = '我的学期',
    DateTime? week1Start,
    int totalWeeks = 20,
    List<ClassPeriod> periods = kDefaultPeriods,
  }) {
    return ScheduleData(
      campus: campus,
      semester: Semester(
        name: semesterName,
        week1Start: week1Start ?? mondayOfDate(DateTime.now()),
        totalWeeks: totalWeeks,
      ),
      periods: periods,
      courses: const <Course>[],
    );
  }

  factory ScheduleData.fromJson(Map<String, dynamic> json) {
    final rawPeriods = json['periods'];
    final periods = <ClassPeriod>[];
    if (rawPeriods is List) {
      for (final item in rawPeriods) {
        if (item is Map) {
          periods.add(ClassPeriod.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    periods.sort((a, b) => a.node.compareTo(b.node));

    final rawCourses = json['courses'];
    final courses = <Course>[];
    if (rawCourses is List) {
      for (var i = 0; i < rawCourses.length; i++) {
        final item = rawCourses[i];
        if (item is Map) {
          courses.add(
            Course.fromJson(Map<String, dynamic>.from(item), index: i),
          );
        }
      }
    }

    final rawSemester = json['semester'];
    return ScheduleData(
      campus: json['campus'] as String? ?? '',
      semester: Semester.fromJson(
        rawSemester is Map
            ? Map<String, dynamic>.from(rawSemester)
            : <String, dynamic>{},
      ),
      periods: periods,
      courses: courses,
    );
  }

  /// 从 JSON 文本解析课表。
  static ScheduleData parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('课表数据格式不对：最外层应该是一个对象');
    }
    return ScheduleData.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 序列化成 JSON 文本（以后做「导出 / 分享给同学」会用到）。
  String toJsonString({bool pretty = false}) {
    final map = <String, dynamic>{
      'campus': campus,
      'semester': semester.toJson(),
      'periods': periods.map((p) => p.toJson()).toList(),
      'courses': courses.map((c) => c.toJson()).toList(),
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  /// 把这份数据和算法打包成计算器，界面直接用。
  WeekCalculator get calculator =>
      WeekCalculator(semester: semester, courses: courses, periods: periods);

  /// 换一批课程，其他信息不变（阶段 3 编辑课程后调用）。
  ScheduleData copyWith({
    String? campus,
    Semester? semester,
    List<ClassPeriod>? periods,
    List<Course>? courses,
  }) {
    return ScheduleData(
      campus: campus ?? this.campus,
      semester: semester ?? this.semester,
      periods: periods ?? this.periods,
      courses: courses ?? this.courses,
    );
  }
}

/// 一门课的上课规律。
enum WeekRule {
  /// 每周都上。
  every,

  /// 只在单周（第 1、3、5… 周）上。
  odd,

  /// 只在双周（第 2、4、6… 周）上。
  even,

  /// 自定义：由 [Course.customWeeks] 明确列出要上的周次。
  custom;

  /// 从 JSON 里的 EVERY / ODD / EVEN / CUSTOM 转成枚举。
  static WeekRule fromCode(String? code) {
    switch ((code ?? '').toUpperCase()) {
      case 'EVERY':
        return WeekRule.every;
      case 'ODD':
        return WeekRule.odd;
      case 'EVEN':
        return WeekRule.even;
      default:
        return WeekRule.custom;
    }
  }

  /// 写回 JSON 用的代号。
  String get code {
    switch (this) {
      case WeekRule.every:
        return 'EVERY';
      case WeekRule.odd:
        return 'ODD';
      case WeekRule.even:
        return 'EVEN';
      case WeekRule.custom:
        return 'CUSTOM';
    }
  }

  /// 给人看的中文名。
  String get label {
    switch (this) {
      case WeekRule.every:
        return '每周';
      case WeekRule.odd:
        return '单周';
      case WeekRule.even:
        return '双周';
      case WeekRule.custom:
        return '自定义';
    }
  }
}

/// 把「每周 / 单周 / 双周 / 自定义」加上起止周，展开成具体的周次列表。
///
/// 例：单周、第 3 周到第 9 周 → [3, 5, 7, 9]
List<int> expandWeeks({
  required WeekRule rule,
  required int startWeek,
  required int endWeek,
  List<int> customWeeks = const <int>[],
}) {
  if (rule == WeekRule.custom) {
    return customWeeks.where((w) => w >= 1).toSet().toList()..sort();
  }

  final from = startWeek < 1 ? 1 : startWeek;
  final to = endWeek < from ? from : endWeek;

  final result = <int>[];
  for (var w = from; w <= to; w++) {
    switch (rule) {
      case WeekRule.every:
        result.add(w);
        break;
      case WeekRule.odd:
        if (w.isOdd) result.add(w);
        break;
      case WeekRule.even:
        if (w.isEven) result.add(w);
        break;
      case WeekRule.custom:
        break;
    }
  }
  return result;
}

/// 一条「上课安排」：某门课在星期几的第几节、哪些周上、在哪个教室。
///
/// 注意：同一门课如果一周上三次，这里会存成三条记录——每条代表一个固定的时间段。
class Course {
  /// 唯一标识，用来区分不同记录。
  final String id;

  /// 课程名称，例如「高等数学B（上）」。
  final String courseName;

  /// 任课教师。
  final String teacher;

  /// 课程代码（教务系统给的编号）。
  final String courseCode;

  /// 星期几，1=周一 … 7=周日。
  final int dayOfWeek;

  /// 第几节，从 1 开始。
  final int node;

  /// 周次规则。
  final WeekRule weekRule;

  /// 起始周。
  final int startWeek;

  /// 结束周。
  final int endWeek;

  /// 仅当 [weekRule] 为 custom 时使用。
  final List<int> customWeeks;

  /// 教室，例如「一教101」；可能为空（比如体育课）。
  final String classroom;

  /// 特殊调整：周次 → 这一周是否要上。
  ///
  /// 这是给「调休 / 临时停课 / 补课」用的，例如国庆放假那一周写成
  /// `{5: false}` 就表示第 5 周虽然按规律该上，但实际不上。
  /// 没写进这个表的周次，一律按 [weekRule] 的规律算。
  final Map<int, bool> overrides;

  const Course({
    required this.id,
    required this.courseName,
    required this.teacher,
    required this.courseCode,
    required this.dayOfWeek,
    required this.node,
    required this.weekRule,
    required this.startWeek,
    required this.endWeek,
    this.customWeeks = const <int>[],
    this.classroom = '',
    this.overrides = const <int, bool>{},
  });

  factory Course.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final courseName = json['courseName'] as String? ?? '未命名课程';
    final courseCode = json['courseCode'] as String? ?? '';
    final dayOfWeek = (json['dayOfWeek'] as num?)?.toInt() ?? 1;
    final node = (json['node'] as num?)?.toInt() ?? 1;

    final rawWeeks = json['weeks'];
    final customWeeks = <int>[];
    if (rawWeeks is List) {
      for (final w in rawWeeks) {
        if (w is num) customWeeks.add(w.toInt());
      }
    }

    final overrides = <int, bool>{};
    final rawOverrides = json['overrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        final week = int.tryParse(key.toString());
        if (week != null && value is bool) overrides[week] = value;
      });
    }

    return Course(
      id:
          json['id'] as String? ??
          '${courseCode.isEmpty ? courseName : courseCode}#$dayOfWeek-$node-$index',
      courseName: courseName,
      teacher: json['teacher'] as String? ?? '',
      courseCode: courseCode,
      dayOfWeek: dayOfWeek,
      node: node,
      weekRule: WeekRule.fromCode(json['weekRule'] as String?),
      startWeek: (json['startWeek'] as num?)?.toInt() ?? 1,
      endWeek: (json['endWeek'] as num?)?.toInt() ?? 1,
      customWeeks: customWeeks,
      classroom: json['classroom'] as String? ?? '',
      overrides: overrides,
    );
  }

  /// 换掉其中几项，其余保持不变（阶段 3 的编辑表单改完课就用它生成新对象）。
  Course copyWith({
    String? id,
    String? courseName,
    String? teacher,
    String? courseCode,
    int? dayOfWeek,
    int? node,
    WeekRule? weekRule,
    int? startWeek,
    int? endWeek,
    List<int>? customWeeks,
    String? classroom,
    Map<int, bool>? overrides,
  }) {
    return Course(
      id: id ?? this.id,
      courseName: courseName ?? this.courseName,
      teacher: teacher ?? this.teacher,
      courseCode: courseCode ?? this.courseCode,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      node: node ?? this.node,
      weekRule: weekRule ?? this.weekRule,
      startWeek: startWeek ?? this.startWeek,
      endWeek: endWeek ?? this.endWeek,
      customWeeks: customWeeks ?? this.customWeeks,
      classroom: classroom ?? this.classroom,
      overrides: overrides ?? this.overrides,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseName': courseName,
    'teacher': teacher,
    'courseCode': courseCode,
    'dayOfWeek': dayOfWeek,
    'node': node,
    'weekRule': weekRule.code,
    'startWeek': startWeek,
    'endWeek': endWeek,
    'weeks': customWeeks,
    'classroom': classroom,
    'overrides': overrides.map((k, v) => MapEntry(k.toString(), v)),
  };

  /// 展开后的上课周次（单纯按规则算，不含 [overrides] 的临时调整）。
  List<int> get weeks => expandWeeks(
    rule: weekRule,
    startWeek: startWeek,
    endWeek: endWeek,
    customWeeks: customWeeks,
  );

  /// 第一次上课的周次；没有任何周次时返回 0。
  int get firstWeek => weeks.isEmpty ? 0 : weeks.first;

  /// 最后一次上课的周次。
  int get lastWeek => weeks.isEmpty ? 0 : weeks.last;

  /// 第 [week] 周是否要上这门课（已经考虑调休等特殊调整）。
  bool isActiveInWeek(int week) {
    final override = overrides[week];
    if (override != null) return override;
    return weeks.contains(week);
  }

  /// 时间段的唯一键：星期 + 节次（同一个格子只能放一门课）。
  String get slotKey => '$dayOfWeek-$node';

  /// 给人看的上课规律，例如「每周 第3-15周」。
  String get ruleText => '${weekRule.label} 第$startWeek-$endWeek周';

  @override
  String toString() =>
      '$courseName（周$dayOfWeek 第$node节 $ruleText'
      '${classroom.isEmpty ? '' : ' $classroom'}）';
}

/// 学期信息：第 1 周从哪天开始、一学期共多少周。
///
/// 课表里最重要的换算就是它：把「今天」换算成「第几周」。
/// 所有单双周、第 N 周上不上课，都建立在这个换算之上。
class Semester {
  /// 学期名称，例如「2026-2027 学年 秋季学期」。
  final String name;

  /// 第 1 周的周一（只保留年月日，不含时分秒）。
  final DateTime week1Start;

  /// 学期总周数。
  final int totalWeeks;

  Semester({
    required this.name,
    required DateTime week1Start,
    required this.totalWeeks,
  }) : week1Start = DateTime(week1Start.year, week1Start.month, week1Start.day);

  factory Semester.fromJson(Map<String, dynamic> json) {
    final raw = json['week1Start'] as String? ?? '';
    return Semester(
      name: json['name'] as String? ?? '我的学期',
      week1Start: DateTime.tryParse(raw) ?? DateTime.now(),
      totalWeeks: (json['totalWeeks'] as num?)?.toInt() ?? 20,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'week1Start': formatDate(week1Start),
    'totalWeeks': totalWeeks,
  };

  /// 换掉其中某几项，其余保持不变。
  Semester copyWith({String? name, DateTime? week1Start, int? totalWeeks}) {
    return Semester(
      name: name ?? this.name,
      week1Start: week1Start ?? this.week1Start,
      totalWeeks: totalWeeks ?? this.totalWeeks,
    );
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 这一天属于第几周（从 1 开始算）。
  /// 开学之前会返回 0 或负数，学期结束之后会大于 [totalWeeks]。
  int weekOf(DateTime date) {
    final diff = dateOnly(date).difference(week1Start).inDays;
    // 用 floor 除法，这样开学前的日期不会算成第 1 周。
    return (diff / 7).floor() + 1;
  }

  /// 今天是第几周。
  int currentWeek([DateTime? now]) => weekOf(now ?? DateTime.now());

  /// 这一周是否落在学期范围内。
  bool containsWeek(int week) => week >= 1 && week <= totalWeeks;

  /// 第 [week] 周的周一。
  DateTime mondayOfWeek(int week) =>
      week1Start.add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周、星期 [dayOfWeek]（1=周一 … 7=周日）对应的日期。
  DateTime dateOf(int week, int dayOfWeek) =>
      mondayOfWeek(week).add(Duration(days: dayOfWeek - 1));

  /// 奇数周叫「单周」，偶数周叫「双周」。
  static bool isOddWeek(int week) => week.isOdd;

  static String parityLabel(int week) => week.isOdd ? '单周' : '双周';

  /// 把日期格式化成 2026-10-14 这样。
  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  String toString() => '$name（第1周 $week1Start 开始，共 $totalWeeks 周）';
}

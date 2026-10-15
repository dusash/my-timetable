import '../models/class_period.dart';
import '../models/course.dart';
import '../models/semester.dart';

/// 课表的核心算法都在这里。
///
/// 它只回答一个问题：**给定第几周，应该显示哪些课？**
/// 界面（阶段 2）只管把它算出来的结果画出来，不自己判断周次——这样规则只有一处，
/// 以后改规则（比如加调休）不用满项目找。
class WeekCalculator {
  /// 学期信息（用来换算「今天 = 第几周」）。
  final Semester semester;

  /// 所有上课安排。
  final List<Course> courses;

  /// 作息时间表，用来判断「现在这一节上完了没有」。
  final List<ClassPeriod> periods;

  const WeekCalculator({
    required this.semester,
    required this.courses,
    this.periods = const <ClassPeriod>[],
  });

  // ---------------------------------------------------------------- 周次查询

  /// 第 [week] 周要上的全部课程，按「星期 → 节次」排序。
  List<Course> coursesOfWeek(int week) {
    final result = courses.where((c) => c.isActiveInWeek(week)).toList();
    result.sort((a, b) {
      final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (byDay != 0) return byDay;
      return a.node.compareTo(b.node);
    });
    return result;
  }

  /// 第 [week] 周、星期 [dayOfWeek] 要上的课程（已按节次排序）。
  List<Course> coursesOfDay(int week, int dayOfWeek) {
    return coursesOfWeek(week).where((c) => c.dayOfWeek == dayOfWeek).toList();
  }

  /// 某个格子（第 [week] 周、星期 [dayOfWeek]、第 [node] 节）上的是哪门课。
  /// 没课返回 null。
  Course? courseAt(int week, int dayOfWeek, int node) {
    for (final c in courses) {
      if (c.dayOfWeek == dayOfWeek && c.node == node && c.isActiveInWeek(week)) {
        return c;
      }
    }
    return null;
  }

  /// 整周的网格数据：星期 → （节次 → 课程）。阶段 2 画课表网格直接用这个。
  Map<int, Map<int, Course>> weekGrid(int week) {
    final grid = <int, Map<int, Course>>{};
    for (final c in coursesOfWeek(week)) {
      grid.putIfAbsent(c.dayOfWeek, () => <int, Course>{})[c.node] = c;
    }
    return grid;
  }

  /// 第 [week] 周一共上了几节课（按时段算，连堂算两节）。
  int activeCountOfWeek(int week) => coursesOfWeek(week).length;

  /// 所有出现过的不重复课程名，方便以后做「按课查看」。
  List<String> distinctCourseNames() {
    final names = courses.map((c) => c.courseName).toSet().toList()..sort();
    return names;
  }

  /// 课表里实际用到的最小 / 最大节次，用来决定网格画几行。
  int get minNode =>
      courses.isEmpty ? 1 : courses.map((c) => c.node).reduce((a, b) => a < b ? a : b);

  int get maxNode =>
      courses.isEmpty ? 1 : courses.map((c) => c.node).reduce((a, b) => a > b ? a : b);

  // ------------------------------------------------------------ 「现在 / 下一节」

  /// [node] 节对应的作息时间，没有就返回 null。
  ClassPeriod? periodOf(int node) {
    for (final p in periods) {
      if (p.node == node) return p;
    }
    return null;
  }

  /// 此刻正在上的课，或者今天接下来最近的一节课；今天没课了就返回 null。
  Course? currentOrNextCourse([DateTime? now]) {
    final moment = now ?? DateTime.now();
    final week = semester.weekOf(moment);
    if (!semester.containsWeek(week)) return null;

    final today = coursesOfDay(week, moment.weekday);
    if (today.isEmpty) return null;

    final nowMinutes = moment.hour * 60 + moment.minute;
    for (final c in today) {
      final period = periodOf(c.node);
      // 没有作息时间时，退化成「今天剩下的第一节」。
      if (period == null || period.endMinutes > nowMinutes) return c;
    }
    return null;
  }

  /// 今天是本学期的第几天（第 1 周的周一 = 第 1 天）。
  int dayIndexOf(DateTime date) =>
      Semester.dateOnly(date).difference(semester.week1Start).inDays + 1;

  // ---------------------------------------------------------------- 数据体检

  /// 检查同一个格子是否被两门课同时占用（数据错误会导致课表打架）。
  /// 返回人类可读的问题描述，没有问题就是空列表。
  List<String> detectConflicts() {
    final problems = <String>[];

    for (var week = 1; week <= semester.totalWeeks; week++) {
      final occupied = <String, Course>{};
      for (final c in coursesOfWeek(week)) {
        final previous = occupied[c.slotKey];
        if (previous != null) {
          problems.add(
            '第 $week 周 周${c.dayOfWeek}第${c.node}节：'
            '「${previous.courseName}」与「${c.courseName}」冲突',
          );
        } else {
          occupied[c.slotKey] = c;
        }
      }
    }

    return problems;
  }
}

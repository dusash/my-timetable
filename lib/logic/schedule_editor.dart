import '../models/course.dart';

// ============================================================================
// 阶段 3 的「增删改」逻辑。
//
// 这里全是普通函数：进去一个列表、出来一个新列表，不碰界面、不碰文件。
// 好处是能被测试直接验证，而且改课这件事永远只有一处实现。
// ============================================================================

/// 统一的排序规则：先星期、再节次、再起始周、最后课名。
///
/// 课表里同一个格子可能被单双周两门课轮流占用（比如周四第二节），
/// 所以第 3 顺位比较「起始周」，让先开课的那门排在前面，展示更自然。
int compareCourses(Course a, Course b) {
  final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
  if (byDay != 0) return byDay;

  final byNode = a.node.compareTo(b.node);
  if (byNode != 0) return byNode;

  final byStart = a.startWeek.compareTo(b.startWeek);
  if (byStart != 0) return byStart;

  return a.courseName.compareTo(b.courseName);
}

/// 给一门新课生成一个不会和已有课程撞车的 id。
///
/// id 只要在本机课表里唯一就行，不需要什么花哨的算法。
String nextCourseId(List<Course> courses, {String prefix = 'c'}) {
  final used = courses.map((c) => c.id).toSet();
  var n = used.length + 1;
  while (used.contains('$prefix$n')) {
    n++;
  }
  return '$prefix$n';
}

/// 新增或替换一门课：id 已存在就替换那一条，否则追加到末尾。
///
/// 返回值是新列表（原来的列表不动），配合 Flutter 的「数据变化就重画」很顺手。
List<Course> upsertCourseInList(List<Course> courses, Course course) {
  final result = <Course>[...courses];
  final index = result.indexWhere((c) => c.id == course.id);
  if (index >= 0) {
    result[index] = course;
  } else {
    result.add(course);
  }
  result.sort(compareCourses);
  return result;
}

/// 删掉 id 为 [id] 的那门课；找不到就原样返回。
List<Course> removeCourseFromList(List<Course> courses, String id) {
  return courses.where((c) => c.id != id).toList();
}

/// 找出和 [candidate] 抢同一个格子的课程。
///
/// 判定标准有两层，缺一不可：
///   1. 同一天、同一节 —— 物理上就在一个格子里；
///   2. 周次真的有重叠 —— 单周一门、双周一门是**正常的**，不算冲突。
///
/// 返回的列表不含 [candidate] 自己（编辑已有课程时不把自己当冲突）。
List<Course> findCourseConflicts(List<Course> courses, Course candidate) {
  final candidateWeeks = candidate.weeks.toSet();
  if (candidateWeeks.isEmpty) return const <Course>[];

  return courses.where((c) {
    if (c.id == candidate.id) return false;
    if (c.dayOfWeek != candidate.dayOfWeek) return false;
    if (c.node != candidate.node) return false;
    return c.weeks.any(candidateWeeks.contains);
  }).toList();
}

/// 两门课是不是「同一门课的同一节课」。
///
/// 只看排课信息，不看 id 和教师——判重时宁可多留一条也不要漏掉一条。
/// 顺序无所谓：[Course.customWeeks] 会先排序再比。
bool isSameArrangement(Course a, Course b) {
  return a.courseName == b.courseName &&
      a.dayOfWeek == b.dayOfWeek &&
      a.node == b.node &&
      a.weekRule == b.weekRule &&
      a.startWeek == b.startWeek &&
      a.endWeek == b.endWeek &&
      _sameWeeks(a.customWeeks, b.customWeeks);
}

bool _sameWeeks(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  if (a.isEmpty) return true;
  final sortedA = <int>[...a]..sort();
  final sortedB = <int>[...b]..sort();
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}

/// 给一批「外来的」课程（分享码导入、文本解析导入）重新编号。
///
/// 外来课程自带的 id 是别人手机上的编号，直接拿来用可能和本机的撞车，
/// 所以一律作废、重新发号。
List<Course> renumberCourses(List<Course> incoming) {
  final result = <Course>[];
  for (final course in incoming) {
    result.add(course.copyWith(id: nextCourseId(result, prefix: 'i')));
  }
  result.sort(compareCourses);
  return result;
}

/// 把导入的课程「并进」现有课表。
///
/// 已经是同一节课的（[isSameArrangement]）会被跳过，避免导入两次就重复两遍。
/// 返回新列表，以及实际新增了几条。
({List<Course> courses, int added, int skipped}) mergeCoursesIntoList(
  List<Course> existing,
  List<Course> incoming,
) {
  final result = <Course>[...existing];
  var added = 0;
  var skipped = 0;

  for (final course in incoming) {
    if (result.any((c) => isSameArrangement(c, course))) {
      skipped++;
      continue;
    }
    result.add(course.copyWith(id: nextCourseId(result, prefix: 'i')));
    added++;
  }

  result.sort(compareCourses);
  return (courses: result, added: added, skipped: skipped);
}

/// 给某一门课的某一周设「特殊调整」。
///
/// [value] 有三种取值，含义不同：
///   · `false` —— 这周不上（例如国庆放假、老师临时停课）
///   · `true`  —— 这周一定要上（例如放假调休后补课，本来不在这周的课要补上）
///   · `null`  —— 取消调整，回到按 [Course.weekRule] 的规律算
///
/// 课表本身不会被改动，返回的是新列表。
List<Course> setCourseOverrideInList(
  List<Course> courses,
  String id,
  int week,
  bool? value,
) {
  return courses.map((c) {
    if (c.id != id) return c;
    final next = <int, bool>{...c.overrides};
    if (value == null) {
      next.remove(week);
    } else {
      next[week] = value;
    }
    return c.copyWith(overrides: next);
  }).toList();
}

/// 一次给多门课设同一周的调整（「这一周全部停课」这类批量操作）。
///
/// 只对 [courses] 里 id 出现在 [ids] 中的课生效。
List<Course> setWeekOverrideForCourses(
  List<Course> courses,
  Iterable<String> ids,
  int week,
  bool? value,
) {
  final targets = ids.toSet();
  var result = courses;
  for (final id in targets) {
    result = setCourseOverrideInList(result, id, week, value);
  }
  return result;
}

/// 清掉所有课的所有调休设置，回到纯按规律排课。
List<Course> clearAllOverrides(List<Course> courses) {
  return courses
      .map((c) => c.overrides.isEmpty ? c : c.copyWith(overrides: const <int, bool>{}))
      .toList();
}

/// 统计整份课表里一共设了多少条调休。
int countOverrides(List<Course> courses) =>
    courses.fold<int>(0, (sum, c) => sum + c.overrides.length);

/// 把冲突描述成一句人话，给弹窗用。
///
/// 例：`「大学英语读写（1）」也在同一格（每周 第3-17周）`
String describeConflict(Course other) {
  final weeks = other.weeks;
  final weekText = weeks.isEmpty
      ? '没有任何一周要上'
      : weeks.length == 1
      ? '只有第 ${weeks.first} 周'
      : '第 ${weeks.first}-${weeks.last} 周共 ${weeks.length} 周';
  return '「${other.courseName}」也在这一格（${other.weekRule.label}，$weekText）';
}

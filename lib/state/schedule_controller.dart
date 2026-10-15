import 'package:flutter/foundation.dart';

import '../data/schedule_data.dart';
import '../data/schedule_store.dart';
import '../logic/schedule_editor.dart';
import '../models/class_period.dart';
import '../models/course.dart';
import '../models/semester.dart';

// ============================================================================
// 界面和「存哪儿」之间的中间人。
//
// 它做三件事：
//   1. 把课表数据端在手里，界面随时能读；
//   2. 每次改完课，自动存到本机（你不用记得点保存）；
//   3. 数据一变就喊一声（notifyListeners），界面自己重画。
//
// 因为继承自 ChangeNotifier，不用额外引任何状态管理库，Flutter 自带就够。
// ============================================================================

class ScheduleController extends ChangeNotifier {
  ScheduleController({required this.repository});

  final ScheduleRepository repository;

  ScheduleData? _data;
  String? _error;
  bool _loading = true;

  /// 当前课表；还没加载完时为 null。
  ScheduleData? get data => _data;

  /// 加载失败时的错误信息。
  String? get error => _error;

  /// 是否正在加载。
  bool get loading => _loading;

  /// 一门课都还没有（用来决定要不要显示「添加第一门课」的引导）。
  bool get hasNoCourse => (_data?.courses.isEmpty) ?? false;

  /// 从本机读取课表。
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _data = await repository.load();
    } on Object catch (e) {
      _error = '$e';
    }

    _loading = false;
    notifyListeners();
  }

  /// 改完数据统一走这里：先更新界面，再落盘。
  Future<void> _apply(ScheduleData next) async {
    _data = next;
    notifyListeners();
    await repository.save(next);
  }

  /// 新增或修改一门课。
  Future<void> saveCourse(Course course) async {
    final current = _data;
    if (current == null) return;
    await _apply(
      current.copyWith(courses: upsertCourseInList(current.courses, course)),
    );
  }

  /// 删掉一门课。
  Future<void> deleteCourse(String id) async {
    final current = _data;
    if (current == null) return;
    await _apply(
      current.copyWith(courses: removeCourseFromList(current.courses, id)),
    );
  }

  /// 改学期信息（开学日期、总周数、学期名）。
  Future<void> updateSemester(Semester semester) async {
    final current = _data;
    if (current == null) return;
    await _apply(current.copyWith(semester: semester));
  }

  /// 改作息时间表。
  Future<void> updatePeriods(List<ClassPeriod> periods) async {
    final current = _data;
    if (current == null) return;
    final sorted = <ClassPeriod>[...periods]..sort((a, b) => a.node.compareTo(b.node));
    await _apply(current.copyWith(periods: sorted));
  }

  /// 改校区 / 学校名。
  Future<void> updateCampus(String campus) async {
    final current = _data;
    if (current == null) return;
    await _apply(current.copyWith(campus: campus));
  }

  /// 整份替换（导入课表时会用到）。
  Future<void> replaceAll(ScheduleData next) => _apply(next);

  // ------------------------------------------------------------ 阶段 4：调休

  /// 给某门课的某一周设「特殊调整」。
  ///
  /// [value] 为 false 表示这周不上，true 表示这周要上（补课），null 表示取消调整。
  Future<void> setOverride(String courseId, int week, bool? value) async {
    final current = _data;
    if (current == null) return;
    await _apply(
      current.copyWith(
        courses: setCourseOverrideInList(current.courses, courseId, week, value),
      ),
    );
  }

  /// 一次性给多门课设同一周的调整（整周停课 / 整周恢复）。
  Future<void> setOverridesForCourses(
    Iterable<String> courseIds,
    int week,
    bool? value,
  ) async {
    final current = _data;
    if (current == null) return;
    await _apply(
      current.copyWith(
        courses: setWeekOverrideForCourses(
          current.courses,
          courseIds,
          week,
          value,
        ),
      ),
    );
  }

  /// 清空所有调休设置。
  Future<void> clearOverrides() async {
    final current = _data;
    if (current == null) return;
    await _apply(current.copyWith(courses: clearAllOverrides(current.courses)));
  }

  // ------------------------------------------------------------ 阶段 5：导入

  /// 用导入的课表**整份替换**现在的课表（学期设置也会跟着换）。
  Future<void> importReplaceAll(ScheduleData incoming) async {
    await _apply(incoming.copyWith(courses: renumberCourses(incoming.courses)));
  }

  /// 把导入的课表**并进**现在的课表。
  ///
  /// 重复的课会自动跳过，所以导入两次也不会变成双份。
  /// 学期设置以你自己手机上的为准——同学的课表往往是同一所学校同一学期，
  /// 但你的开学日期可能已经自己调过了，不该被覆盖。
  ///
  /// 例外：如果本机课表还是完全空的（新课表、没录过课），那就直接照单全收。
  Future<({int added, int skipped})> importMerge(ScheduleData incoming) async {
    final current = _data;
    if (current == null) return (added: 0, skipped: 0);

    // 「一门课都还没有」= 用户还没开始用，那就连作息一起照单全收 ——
    // 对方学校的作息大概率比通用的那套默认值更贴合实际。
    // （以前这里还要额外判断 periods 为空，但空课表现在自带一套默认作息，
    //   那个条件就永远不成立了，会把这批新用户挡在外面。）
    if (current.courses.isEmpty) {
      await _apply(
        incoming.copyWith(courses: renumberCourses(incoming.courses)),
      );
      return (added: incoming.courses.length, skipped: 0);
    }

    final merged = mergeCoursesIntoList(current.courses, incoming.courses);
    await _apply(
      current.copyWith(
        courses: merged.courses,
        periods: current.periods.isEmpty ? incoming.periods : current.periods,
      ),
    );
    return (added: merged.added, skipped: merged.skipped);
  }

  /// 恢复出厂课表（清掉本机所有改动）。
  Future<void> resetToDefault() async {
    _data = await repository.resetToDefault();
    notifyListeners();
  }
}

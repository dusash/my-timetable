// 阶段 1 自检脚本（纯 Dart，不需要手机、不需要模拟器）。
//
// 用法：在项目根目录执行
//   dart run tool/verify_logic.dart
//
// 它的作用：用你真实课表的数据，把「第 N 周该上哪些课」算一遍并逐条核对，
// 确认数据模型和算法没问题之后，再把 App 跑到手机上。

import 'dart:io';

import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/logic/grid_builder.dart';
import 'package:my_timetable/logic/schedule_editor.dart';
import 'package:my_timetable/logic/schedule_parser.dart';
import 'package:my_timetable/logic/share_code.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/models/semester.dart';

int _passed = 0;
final List<String> _failures = <String>[];

void check(String what, Object? actual, Object? expected) {
  final a = actual?.toString();
  final e = expected?.toString();
  if (a == e) {
    _passed++;
    stdout.writeln('  [通过] $what  →  $a');
  } else {
    _failures.add('$what：期望 $e，实际 $a');
    stdout.writeln('  [不通过] $what  →  期望 $e，实际 $a');
  }
}

void section(String title) {
  stdout.writeln('');
  stdout.writeln('── $title ${'─' * (46 - title.length)}');
}

/// 找到项目里的课表数据文件（不管从哪个目录运行都能找到）。
File _locateDataFile() {
  final candidates = <String>[
    'assets/data/sample_schedule.json',
    'my_timetable/assets/data/sample_schedule.json',
    'D:/projects/my_timetable/assets/data/sample_schedule.json',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) return f;
  }
  throw StateError('找不到 assets/data/sample_schedule.json，请在项目根目录运行本脚本');
}

Future<void> main() async {
  stdout.writeln('═══ 课表 App · 阶段 1 算法自检 ═══');

  // ---------------------------------------------------------- 1. 读取与解析
  section('一、读取真实课表数据');
  final file = _locateDataFile();
  final data = ScheduleData.parse(file.readAsStringSync());
  final calc = data.calculator;

  stdout.writeln('  数据文件：${file.path}');
  stdout.writeln('  学期：${data.semester.name}');
  stdout.writeln('  第 1 周起始：${Semester.formatDate(data.semester.week1Start)}'
      '（共 ${data.semester.totalWeeks} 周）');
  stdout.writeln('  作息时间：${data.periods.length} 大节');
  stdout.writeln('  上课安排：${data.courses.length} 条');

  check('课程条数', data.courses.length, 16);
  check('作息节数', data.periods.length, 6);
  check('全学期不重复课程门数', calc.distinctCourseNames().length, 10);

  // ------------------------------------------------------------ 2. 周次换算
  section('二、日期 → 第几周');
  check('2026-09-06（开学前一天）', data.semester.weekOf(DateTime(2026, 9, 6)), 0);
  check('2026-09-07（开学第一天）', data.semester.weekOf(DateTime(2026, 9, 7)), 1);
  check('2026-09-13（第1周周日）', data.semester.weekOf(DateTime(2026, 9, 13)), 1);
  check('2026-09-14（第2周周一）', data.semester.weekOf(DateTime(2026, 9, 14)), 2);
  check('2026-10-12（第6周周一）', data.semester.weekOf(DateTime(2026, 10, 12)), 6);
  check('2026-10-14（今天）', data.semester.weekOf(DateTime(2026, 10, 14)), 6);
  check('2026-10-18（第6周周日）', data.semester.weekOf(DateTime(2026, 10, 18)), 6);
  check('2026-10-19（第7周周一）', data.semester.weekOf(DateTime(2026, 10, 19)), 7);

  section('三、第几周 → 日期');
  check('第6周周一', Semester.formatDate(data.semester.dateOf(6, 1)), '2026-10-12');
  check('第6周周三', Semester.formatDate(data.semester.dateOf(6, 3)), '2026-10-14');
  check('第6周周日', Semester.formatDate(data.semester.dateOf(6, 7)), '2026-10-18');
  check('第1周周一', Semester.formatDate(data.semester.dateOf(1, 1)), '2026-09-07');

  section('四、单双周');
  check('第 5 周是', Semester.parityLabel(5), '单周');
  check('第 6 周是', Semester.parityLabel(6), '双周');
  check('第 7 周是', Semester.parityLabel(7), '单周');

  // -------------------------------------------------------------- 5. 展开周次
  section('五、周次规则展开');
  Course byName(String name, {int? day, int? node}) {
    return data.courses.firstWhere(
      (c) =>
          c.courseName == name &&
          (day == null || c.dayOfWeek == day) &&
          (node == null || c.node == node),
      orElse: () => throw StateError('找不到课程：$name'),
    );
  }

  check(
    '人文素质教育（单周）',
    byName('人文素质教育').weeks.join(','),
    '5,7,9,11,13,15',
  );
  check(
    '大学英语读写·周四第二节（单周）',
    byName('大学英语读写（1）', day: 4).weeks.join(','),
    '3,5,7,9,11,13,15,17',
  );
  check(
    '大学英语视听说·周四第二节（双周）',
    byName('大学英语视听说（1）').weeks.join(','),
    '4,6,8,10,12,14,16,18',
  );
  check('高等数学B（每周 3-15）', byName('高等数学B（上）').weeks.length, 13);
  check('形势与政策1（9-12）', byName('形势与政策1').weeks.join(','), '9,10,11,12');

  // ------------------------------------------------------------ 6. 本周课程
  section('六、第 6 周实际上课情况');
  final week6 = calc.coursesOfWeek(6);
  check('第 6 周时段数', week6.length, 12);
  check(
    '第 6 周不重复课程门数',
    week6.map((c) => c.courseName).toSet().length,
    7,
  );
  check('第 5 周时段数（单周）', calc.coursesOfWeek(5).length, 12);
  check('第 6 周时段数（双周）', calc.coursesOfWeek(6).length, 12);
  check('第 10 周时段数（双周）', calc.coursesOfWeek(10).length, 13);
  check('第 9 周时段数（单周 + 形势与政策开始，最满的一周）',
      calc.coursesOfWeek(9).length, 14);
  check('第 2 周时段数（还没开学上课）', calc.coursesOfWeek(2).length, 0);

  stdout.writeln('');
  stdout.writeln('  全学期每周时段数分布（看单双周和分段课的效果）：');
  for (var w = 1; w <= data.semester.totalWeeks; w++) {
    final n = calc.coursesOfWeek(w).length;
    final parity = Semester.parityLabel(w);
    final bar = n == 0 ? '' : '█' * n;
    stdout.writeln('    第${w.toString().padLeft(2)}周（$parity）  '
        '${n.toString().padLeft(2)} 节  $bar');
  }

  stdout.writeln('');
  stdout.writeln('  第 6 周课表：');
  for (final c in week6) {
    final period = calc.periodOf(c.node);
    stdout.writeln(
      '    周${c.dayOfWeek} ${period?.label ?? '第${c.node}节'}'
      ' ${period?.range ?? ''}  ${c.courseName}  ${c.teacher}'
      '  ${c.classroom.isEmpty ? '（无教室）' : c.classroom}',
    );
  }

  // ------------------------------------------------------------ 7. 单双周交替
  section('七、同一个格子上的单双周交替（周四第二节）');
  final wed4 = calc.courseAt(6, 4, 2);
  final mon4 = calc.courseAt(5, 4, 2);
  check('第 6 周（双周）周四第二节', wed4?.courseName, '大学英语视听说（1）');
  check('第 5 周（单周）周四第二节', mon4?.courseName, '大学英语读写（1）');
  check('第 6 周周三第一节（人文素质单周）', calc.courseAt(6, 3, 1), null);
  check('第 5 周周三第一节（人文素质单周）', calc.courseAt(5, 3, 1)?.courseName, '人文素质教育');

  section('八、同一时段按周次分段的两门课（周五第四节）');
  check('第 6 周周五第四节', calc.courseAt(6, 5, 4)?.courseName, '心理教育健康');
  check('第 12 周周五第四节', calc.courseAt(12, 5, 4)?.courseName, '职业发展');

  section('九、连堂课（周二第四、五节近代史）');
  check('第 6 周周二第四节', calc.courseAt(6, 2, 4)?.courseName, '中国近现代史纲要');
  check('第 6 周周二第五节', calc.courseAt(6, 2, 5)?.courseName, '中国近现代史纲要');
  check('第 6 周周二上几节', calc.coursesOfDay(6, 2).length, 4);

  // ------------------------------------------------------------ 10. 下一节课
  section('十、「现在上什么 / 下一节上什么」');
  check(
    '周三 09:40 → 接下来',
    calc.currentOrNextCourse(DateTime(2026, 10, 14, 9, 40))?.courseName,
    '高等数学B（上）',
  );
  check(
    '周三 10:30 → 正在上',
    calc.currentOrNextCourse(DateTime(2026, 10, 14, 10, 30))?.courseName,
    '高等数学B（上）',
  );
  check(
    '周三 12:00 → 今天没课了',
    calc.currentOrNextCourse(DateTime(2026, 10, 14, 12, 0)),
    null,
  );
  check(
    '周六 10:00 → 今天没课',
    calc.currentOrNextCourse(DateTime(2026, 10, 17, 10, 0)),
    null,
  );
  check(
    '开学前 2026-09-01 10:00',
    calc.currentOrNextCourse(DateTime(2026, 9, 1, 10, 0)),
    null,
  );

  // ------------------------------------------------------------ 11. 调休覆盖
  section('十一、调休（overrides）能否覆盖默认规律');
  final holiday = Course(
    id: 'test-holiday',
    courseName: '国庆调休测试课',
    teacher: '测试',
    courseCode: 'TEST',
    dayOfWeek: 1,
    node: 1,
    weekRule: WeekRule.every,
    startWeek: 3,
    endWeek: 15,
    overrides: const <int, bool>{5: false, 6: true},
  );
  check('第 3 周（正常该上）', holiday.isActiveInWeek(3), true);
  check('第 5 周（被调休覆盖为不上）', holiday.isActiveInWeek(5), false);
  check('第 6 周（被覆盖为补课）', holiday.isActiveInWeek(6), true);
  check('第 20 周（超出范围）', holiday.isActiveInWeek(20), false);

  // ---------------------------------------------------------- 12. 数据体检
  section('十二、数据体检与序列化');
  final conflicts = calc.detectConflicts();
  check('同一格子被两门课占用的问题数', conflicts.length, 0);
  for (final c in conflicts) {
    stdout.writeln('    · $c');
  }
  final roundTrip = ScheduleData.parse(data.toJsonString());
  check('导出再导入后的课程条数', roundTrip.courses.length, data.courses.length);
  check(
    '导出再导入后学期起始日',
    Semester.formatDate(roundTrip.semester.week1Start),
    Semester.formatDate(data.semester.week1Start),
  );

  // -------------------------------------------------------- 13. 网格排布
  section('十三、网格排布（连堂合并 + 灰色幽灵卡）');

  List<CourseBlock> dayBlocks(int week, int day) => buildDayBlocks(
    calc,
    week: week,
    day: day,
    minNode: calc.minNode,
    maxNode: calc.maxNode,
  );

  final tue6 = dayBlocks(6, 2);
  check('第6周周二 块数（连堂合并后）', tue6.length, 3);
  check(
    '第6周周二 第四节的块跨几节（连堂应合并）',
    tue6.firstWhere((b) => b.startNode == 4).span,
    2,
  );

  final thu6 = dayBlocks(6, 4);
  check('第6周周四 块数', thu6.length, 3);
  check(
    '第6周周四 依次是',
    thu6.map((b) => b.course.courseName).join(' / '),
    '计算机导论与程序设计基础 / 大学英语视听说（1） / 形势与政策1',
  );
  check('第6周周四 幽灵块数', thu6.where((b) => b.isGhost).length, 1);

  final wed6 = dayBlocks(6, 3);
  check(
    '第6周周三 的幽灵块（单周才上的人文素质教育）',
    wed6.where((b) => b.isGhost).map((b) => b.course.courseName).join(','),
    '人文素质教育',
  );

  var ghostCount6 = 0;
  for (var d = 1; d <= 5; d++) {
    ghostCount6 += dayBlocks(6, d).where((b) => b.isGhost).length;
  }
  check('第6周 周一到周五 幽灵卡总数', ghostCount6, 2);

  final fri12 = dayBlocks(12, 5);
  check('第12周周五 块数', fri12.length, 3);
  check('第12周周五 幽灵块数', fri12.where((b) => b.isGhost).length, 0);
  check(
    '第12周周五 第四节的课',
    fri12.firstWhere((b) => b.startNode == 4).course.courseName,
    '职业发展',
  );

  stdout.writeln('');
  stdout.writeln('  第 6 周网格（周一~周五，灰底表示本周不上）：');
  for (var d = 1; d <= 5; d++) {
    stdout.writeln('    周$d  ${dayBlocks(6, d).join('  |  ')}');
  }

  // ------------------------------------------------- 14. 增删改与本地保存
  section('十四、增删改与本地保存（阶段 3）');

  // 新增一门课
  final newCourse = Course(
    id: nextCourseId(data.courses),
    courseName: '人工智能导论',
    teacher: '张老师',
    courseCode: '',
    dayOfWeek: 6,
    node: 1,
    weekRule: WeekRule.every,
    startWeek: 1,
    endWeek: 16,
    classroom: '东1-101',
  );
  check(
    '新生成的 id 不会和已有的撞车',
    data.courses.any((c) => c.id == newCourse.id),
    false,
  );

  final added = upsertCourseInList(data.courses, newCourse);
  check('新增一门课之后的总数', added.length, data.courses.length + 1);
  check('新课排在周六（列表已排序）', added.last.courseName, '人工智能导论');

  // 改一门课（改教室）
  final target = data.courses.first;
  final edited = upsertCourseInList(
    data.courses,
    target.copyWith(classroom: '换过的教室'),
  );
  check('改教室之后，课程总数不变', edited.length, data.courses.length);

  // 删一门课
  final removed = removeCourseFromList(added, newCourse.id);
  check('删掉刚加的那门之后的总数', removed.length, data.courses.length);
  check(
    '删掉的目标确实不在了',
    removed.any((c) => c.id == newCourse.id),
    false,
  );

  // 冲突检测
  final thuEven = data.courses.firstWhere(
    (c) => c.courseName.contains('视听说'),
  );
  check(
    '只改教室（同一天同一节）不算冲突',
    findCourseConflicts(data.courses, thuEven.copyWith(classroom: '别的教室')).length,
    0,
  );
  check(
    '单双周轮换不算冲突（视听说 + 读写共用周四第二节）',
    findCourseConflicts(
      data.courses.where((c) => c.courseName.contains('读写')).toList(),
      thuEven,
    ).length,
    0,
  );

  final clash = thuEven.copyWith(
    weekRule: WeekRule.every,
    startWeek: 1,
    endWeek: 20,
  );
  final clashes = findCourseConflicts(data.courses, clash);
  check('把周四第二节改成每周都上，就会和单周那门课冲突', clashes.length, 1);
  check(
    '冲突对象是读写',
    clashes.single.courseName.contains('读写'),
    true,
  );
  check(
    '冲突描述读得懂',
    describeConflict(clashes.single).contains('大学英语读写'),
    true,
  );
  check('真实课表本身没有任何冲突', calc.detectConflicts().length, 0);

  // 本地保存（用内存版存档，不碰磁盘）
  final store = MemoryScheduleStore();
  final repo = ScheduleRepository(store: store, seedJson: data.toJsonString());

  final firstOpen = await repo.load();
  check('第一次打开：用出厂课表', firstOpen.courses.length, data.courses.length);
  check('第一次打开后已经顺手存档', (await store.read()) != null, true);

  await repo.save(data.copyWith(courses: removed));
  final secondOpen = await repo.load();
  check('保存之后第二次打开：用的是用户那份', secondOpen.courses.length, removed.length);
  check(
    '删掉的那门课没有残留在存档里',
    (await store.read())!.contains('人工智能导论'),
    false,
  );

  final broken = MemoryScheduleStore('{ 这不是合法的 JSON');
  final recovered = await ScheduleRepository(
    store: broken,
    seedJson: data.toJsonString(),
  ).load();
  check(
    '存档坏掉时给一份空课表（App 不会打不开）',
    recovered.courses.length,
    0,
  );
  check(
    '坏掉的存档原样留着没被覆盖（万一还能手工抢救）',
    await broken.read(),
    '{ 这不是合法的 JSON',
  );

  // 正式 App 不传 seed：第一次打开应该是一份干净的空课表，
  // 但要自带一套作息，否则用户连「第几节」都没得选。
  final freshRepo = ScheduleRepository(store: MemoryScheduleStore());
  final fresh = await freshRepo.load();
  check('出厂状态：一门课都不预装', fresh.courses.length, 0);
  check('出厂状态：默认作息要够用（10 节）', fresh.periods.length, 10);
  check('出厂状态：开学日期落在周一', fresh.semester.week1Start.weekday, 1);

  // -------------------------------------------- 15. 调休（阶段 4）
  section('十五、调休：停课 / 补课 / 取消（阶段 4）');

  final weekly = data.courses.firstWhere(
    (c) => c.weekRule == WeekRule.every && c.endWeek - c.startWeek >= 5,
  );
  final restWeek = weekly.startWeek + 1;
  check('挑一门每周课，第 $restWeek 周本来要上', weekly.isActiveInWeek(restWeek), true);

  var withOverride = setCourseOverrideInList(
    data.courses,
    weekly.id,
    4,
    false,
  );
  var changed = withOverride.firstWhere((c) => c.id == weekly.id);
  check('设成「这周不上」之后，第 4 周就不出现了', changed.isActiveInWeek(4), false);
  check('其他周不受影响（第 5 周照常）', changed.isActiveInWeek(5), true);

  withOverride = setCourseOverrideInList(data.courses, weekly.id, 4, null);
  changed = withOverride.firstWhere((c) => c.id == weekly.id);
  check('取消调整后回到原来的规律', changed.isActiveInWeek(4), true);
  check('取消调整后没有残留记录', changed.overrides.length, 0);

  final oddCourse = data.courses.firstWhere((c) => c.weekRule == WeekRule.odd);
  final evenWeek = oddCourse.weeks.first + 1;
  check(
    '单周课在双周（第 $evenWeek 周）本来不上',
    oddCourse.isActiveInWeek(evenWeek),
    false,
  );
  withOverride = setCourseOverrideInList(
    data.courses,
    oddCourse.id,
    evenWeek,
    true,
  );
  check(
    '设成「这周一定上」之后能强行补课',
    withOverride.firstWhere((c) => c.id == oddCourse.id).isActiveInWeek(evenWeek),
    true,
  );

  final allIds = data.courses.map((c) => c.id).toList();
  final stoppedAll = setWeekOverrideForCourses(data.courses, allIds, 6, false);
  check(
    '整周批量停课后，第 6 周一节都不剩',
    stoppedAll.where((c) => c.isActiveInWeek(6)).length,
    0,
  );
  check('整周停课一共留下多少条调休', countOverrides(stoppedAll), allIds.length);
  check('一键清空调休', countOverrides(clearAllOverrides(stoppedAll)), 0);

  // ---------------------------------------- 16. 分享码（阶段 5）
  section('十六、分享码：编码 / 解码 / 压缩效果（阶段 5）');

  final rawJson = data.toJsonString();
  final code = ShareCode.encode(data);
  final decoded = ShareCode.decode(code);

  check('分享码以 KTB1: 开头', code.startsWith('$kShareCodePrefix:'), true);
  stdout.writeln('  原始 JSON：${rawJson.length} 字符');
  stdout.writeln('  分享码　：${code.length} 字符');
  check('分享码比原始 JSON 短一半以上', code.length < rawJson.length ~/ 2, true);
  check('分享码能画成二维码', ShareCode.fitsInQrCode(code), true);
  check('解码后课程条数一致', decoded.courses.length, data.courses.length);
  check('解码后学期名一致', decoded.semester.name, data.semester.name);
  check('解码后作息节数一致', decoded.periods.length, data.periods.length);
  check(
    '解码后第一条课名一致',
    decoded.courses.first.courseName,
    data.courses.first.courseName,
  );
  check(
    '解码后单双周规则一致',
    decoded.courses.map((c) => c.weekRule.code).join(','),
    data.courses.map((c) => c.weekRule.code).join(','),
  );

  final messy = '我的课表给你：\n  $code  \n收到回我一下';
  check('夹在聊天记录里也能认出来', ShareCode.decode(messy).courses.length, 16);

  var rejectedAsExpected = false;
  try {
    ShareCode.decode('今天晚上吃什么');
  } on ShareCodeException {
    rejectedAsExpected = true;
  }
  check('粘一段无关的话会被明确拒绝', rejectedAsExpected, true);

  // ------------------------------------ 17. 教务文本解析（阶段 5）
  section('十七、教务系统文本解析（阶段 5）');

  const sampleText = '''
高等数学B（上） 周一 第1-2节 3-15周 教5-201 张三
大学英语读写（1） 周四 第2节 3-17周(单) 东12-301 李四
大学英语视听说（1） 周四 第2节 4-18周(双) 东12-301 李四
''';
  final parsed = parseScheduleText(sampleText);
  check('3 行文本解析出 4 条安排（连堂拆成两条）', parsed.courses.length, 4);
  check('识别出 3 门不重复的课', parsed.courseNameCount, 3);

  final mathCourse = parsed.courses.firstWhere((c) => c.node == 1);
  check('课名', mathCourse.courseName, '高等数学B（上）');
  check('教师', mathCourse.teacher, '张三');
  check('教室', mathCourse.classroom, '教5-201');
  check('起止周', '${mathCourse.startWeek}-${mathCourse.endWeek}', '3-15');

  final englishOdd = parsed.courses.firstWhere(
    (c) => c.dayOfWeek == 4 && c.weekRule == WeekRule.odd,
  );
  check('(单) 被认成单周', englishOdd.weekRule.label, '单周');
  check('单周课名', englishOdd.courseName, '大学英语读写（1）');

  final noise = parseScheduleText('随便写点什么\n高等数学 周一 第1节 1-16周');
  check('认不出的行会被收集而不是丢掉', noise.unrecognized.length, 1);

  // ------------------------------------------------------------------ 汇总
  stdout.writeln('');
  stdout.writeln('═' * 52);
  if (_failures.isEmpty) {
    stdout.writeln('全部通过：$_passed 项 ✓  数据模型与周次算法没有问题');
  } else {
    stdout.writeln('通过 $_passed 项，失败 ${_failures.length} 项：');
    for (final f in _failures) {
      stdout.writeln('  ✗ $f');
    }
    exitCode = 1;
  }
  stdout.writeln('═' * 52);
}

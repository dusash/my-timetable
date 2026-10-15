import '../models/course.dart';

// ============================================================================
// 从「教务系统复制出来的课表文本」里认出课程。
//
// 教务系统五花八门，导出的格式也各不相同，所以这里不追求 100% 准确，
// 而是走一条「宽容但讲道理」的路线：
//
//   1. 把整段文本按行处理，凡是有「星期X」的行都当成一门课的开头；
//   2. 从这门课的开头到下一门课的开头，中间的文本合起来当作一条记录；
//   3. 在这段文本里依次找出 星期 → 节次 → 周次 → 教室，
//      匹配到就把这一段「挖掉」；
//   4. 剩下的文字就是课名（还多出一小段就当成教师名）。
//
// 这样不管是「一行一门课」还是「一个字段一行」的格式都能认。
// 认不出来的行会原样收集到 [ParseResult.unrecognized] 里，
// 让界面给用户看，而不是悄悄丢掉。
// ============================================================================

/// 一次文本解析的结果。
class ParseResult {
  const ParseResult({
    required this.courses,
    required this.unrecognized,
    required this.lineCount,
    this.semesterHint,
  });

  /// 解析出来的上课安排（一门课一周上两次就是两条）。
  final List<Course> courses;

  /// 没能认出来的文本片段，给界面提示用。
  final List<String> unrecognized;

  /// 一共读了几行（用来告诉用户「这么长的文本里认出了多少」）。
  final int lineCount;

  /// 文本里如果写着「第 1 周」「2026-09-07」这类信息，顺手记下来。
  /// 现在还没用它自动改学期设置，先留着给界面展示。
  final String? semesterHint;

  bool get isEmpty => courses.isEmpty;

  /// 去重后的课程名数量，界面显示「识别到 N 门课」用这个。
  int get courseNameCount =>
      courses.map((c) => c.courseName).toSet().length;
}

const Map<String, int> _weekdayChars = <String, int>{
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '日': 7,
  '天': 7,
};

/// 「星期X」「周X」。
final RegExp _weekdayRe = RegExp(r'(?:星期|周)([一二三四五六日天])');

/// 「第1-2节」「第1,2节」「第3节」。
final RegExp _nodeRe = RegExp(
  r'第?\s*(\d{1,2})\s*(?:[-－~–—至到,，、]\s*(\d{1,2}))?\s*节',
);

/// 「第3-15周」「3-15周」「1,3,5周」「5周」。
final RegExp _weekRangeRe = RegExp(r'第?\s*(\d{1,2})\s*[-－~–—至到]\s*(\d{1,2})\s*周');
final RegExp _weekListRe = RegExp(r'第?\s*((?:\d{1,2}\s*[,，、]\s*)+\d{1,2})\s*周');
final RegExp _weekSingleRe = RegExp(r'第?\s*(\d{1,2})\s*周');

/// 教室：带连字符的编号（一教101、东12-301、教5-201）。
final RegExp _roomDashRe = RegExp(
  r'(?:[A-Za-z\u4e00-\u9fa5]{0,2})?\d{1,3}\s*[-－]\s*\d{1,4}[A-Za-z]?(?!\s*[周节])',
);

/// 教室：无连字符的短编号（A101、B203）。
final RegExp _roomShortRe = RegExp(r'\b[A-Za-z]\d{3,4}\b');

/// 单周 / 双周的各种写法。
///
/// 故意不收「单独的『单』字」——课名里出现「单片机」这种词时会被误伤，
/// 而括号形式和「单周」二字已经覆盖了教务系统的常见写法。
final RegExp _oddRe = RegExp(r'\(单\)|（单）|\[单\]|单周');
final RegExp _evenRe = RegExp(r'\(双\)|（双）|\[双\]|双周');

/// 把一整段课表文本解析成课程。
///
/// [defaultTotalWeeks] 用来兜底：文本里没写清楚周次时，按整学期算。
ParseResult parseScheduleText(String text, {int defaultTotalWeeks = 20}) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.isEmpty) {
    return const ParseResult(
      courses: <Course>[],
      unrecognized: <String>[],
      lineCount: 0,
    );
  }

  // 第 1 步：以「含星期X 的行」为界，把文本切成一条条记录。
  final records = <List<String>>[];
  var current = <String>[];

  for (final line in lines) {
    final startsNew = _weekdayRe.hasMatch(line);
    if (startsNew && current.isNotEmpty) {
      records.add(current);
      current = <String>[];
    }
    current.add(line);
  }
  if (current.isNotEmpty) records.add(current);

  // 第 2 步：逐条记录抽字段。
  final courses = <Course>[];
  final unrecognized = <String>[];
  var serial = 0;

  for (final record in records) {
    final joined = record.join(' ');
    final parsed = _parseRecord(joined, defaultTotalWeeks: defaultTotalWeeks);
    if (parsed == null) {
      // 认不出来就留着给用户看，但整行是表格噪音的（纯数字）就跳过。
      final noise = record.every((l) => RegExp(r'^[\d\s\-—]+$').hasMatch(l));
      if (!noise) unrecognized.add(joined);
      continue;
    }

    for (final node in parsed.nodes) {
      serial++;
      courses.add(
        Course(
          id: 'p$serial',
          courseName: parsed.courseName,
          teacher: parsed.teacher,
          courseCode: '',
          dayOfWeek: parsed.dayOfWeek,
          node: node,
          weekRule: parsed.rule,
          startWeek: parsed.startWeek,
          endWeek: parsed.endWeek,
          customWeeks: parsed.customWeeks,
          classroom: parsed.classroom,
        ),
      );
    }
  }

  return ParseResult(
    courses: courses,
    unrecognized: unrecognized,
    lineCount: lines.length,
  );
}

/// 一条记录的解析中间结果。
class _ParsedRecord {
  _ParsedRecord({
    required this.courseName,
    required this.teacher,
    required this.dayOfWeek,
    required this.nodes,
    required this.rule,
    required this.startWeek,
    required this.endWeek,
    required this.customWeeks,
    required this.classroom,
  });

  final String courseName;
  final String teacher;
  final int dayOfWeek;
  final List<int> nodes;
  final WeekRule rule;
  final int startWeek;
  final int endWeek;
  final List<int> customWeeks;
  final String classroom;
}

/// 解析一条记录；连星期都找不到就返回 null。
_ParsedRecord? _parseRecord(String text, {required int defaultTotalWeeks}) {
  var rest = text;

  // ---- 星期 -------------------------------------------------------------
  final weekdayMatch = _weekdayRe.firstMatch(rest);
  if (weekdayMatch == null) return null;
  final dayOfWeek = _weekdayChars[weekdayMatch.group(1)!] ?? 1;
  rest = _cut(rest, weekdayMatch);

  // ---- 节次 -------------------------------------------------------------
  final nodeMatch = _nodeRe.firstMatch(rest);
  if (nodeMatch == null) return null; // 没有节次就没法排进课表
  final from = int.parse(nodeMatch.group(1)!);
  final to = nodeMatch.group(2) == null ? from : int.parse(nodeMatch.group(2)!);
  final nodes = <int>[];
  for (var n = from; n <= to && n >= 1; n++) {
    nodes.add(n);
  }
  if (nodes.isEmpty) nodes.add(from);
  rest = _cut(rest, nodeMatch);

  // ---- 周次 -------------------------------------------------------------
  var rule = WeekRule.every;
  var startWeek = 1;
  var endWeek = defaultTotalWeeks;
  var customWeeks = <int>[];

  final rangeMatch = _weekRangeRe.firstMatch(rest);
  final listMatch = _weekListRe.firstMatch(rest);
  final singleMatch = _weekSingleRe.firstMatch(rest);

  if (rangeMatch != null) {
    startWeek = int.parse(rangeMatch.group(1)!);
    endWeek = int.parse(rangeMatch.group(2)!);
    if (endWeek < startWeek) {
      final tmp = startWeek;
      startWeek = endWeek;
      endWeek = tmp;
    }
    rest = _cut(rest, rangeMatch);
  } else if (listMatch != null) {
    final parts = listMatch
        .group(1)!
        .split(RegExp(r'[,，、]'))
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((w) => w >= 1)
        .toList()
      ..sort();
    if (parts.isNotEmpty) {
      rule = WeekRule.custom;
      customWeeks = parts;
      startWeek = parts.first;
      endWeek = parts.last;
    }
    rest = _cut(rest, listMatch);
  } else if (singleMatch != null) {
    startWeek = int.parse(singleMatch.group(1)!);
    endWeek = startWeek;
    rest = _cut(rest, singleMatch);
  }

  // 单双周：在剩下的文本里找「单周 / 双周 / (单) / (双)」。
  if (rule != WeekRule.custom) {
    final oddMatch = _oddRe.firstMatch(rest);
    final evenMatch = _evenRe.firstMatch(rest);
    if (oddMatch != null) {
      rule = WeekRule.odd;
      rest = _cut(rest, oddMatch);
    } else if (evenMatch != null) {
      rule = WeekRule.even;
      rest = _cut(rest, evenMatch);
    }
  }

  // ---- 教室 -------------------------------------------------------------
  var classroom = '';
  final dashRoom = _roomDashRe.firstMatch(rest);
  if (dashRoom != null) {
    classroom = dashRoom.group(0)!.replaceAll(' ', '').replaceAll('－', '-');
    rest = _cut(rest, dashRoom);
  } else {
    final shortRoom = _roomShortRe.firstMatch(rest);
    if (shortRoom != null) {
      classroom = shortRoom.group(0)!;
      rest = _cut(rest, shortRoom);
    }
  }

  // ---- 课名 / 教师 -------------------------------------------------------
  final leftovers = rest
      .split(RegExp(r'[\s,，、|/\\]+'))
      .map((s) => s.trim())
      // 挖走字段后常留下孤零零的括号或破折号，这些不是课名的一部分。
      .where(
        (s) =>
            s.isNotEmpty &&
            !RegExp(r'^[-—~()（）\[\]【】,，、.。:：/\\|]+$').hasMatch(s),
      )
      .toList();

  if (leftovers.isEmpty) return null;

  var courseName = leftovers.first;
  var teacher = '';
  if (leftovers.length >= 2) {
    final last = leftovers.last;
    // 短、纯中文、不含数字 —— 大概率是老师姓名。
    final looksLikeName =
        last.length <= 4 && RegExp(r'^[\u4e00-\u9fa5·]+$').hasMatch(last);
    if (looksLikeName) {
      teacher = last;
      courseName = leftovers.first == last && leftovers.length == 2
          ? leftovers.first
          : leftovers.take(leftovers.length - 1).join(' ');
    } else {
      courseName = leftovers.join(' ');
    }
  }

  courseName = courseName.replaceAll(RegExp(r'^[、,，:：\-\s]+'), '').trim();
  if (courseName.isEmpty) return null;

  return _ParsedRecord(
    courseName: courseName,
    teacher: teacher,
    dayOfWeek: dayOfWeek,
    nodes: nodes,
    rule: rule,
    startWeek: startWeek,
    endWeek: endWeek,
    customWeeks: customWeeks,
    classroom: classroom,
  );
}

/// 把匹配到的片段从文本里「挖掉」，防止同一个片段被后面的规则重复识别。
String _cut(String text, Match match) {
  return text.replaceRange(match.start, match.end, ' ');
}

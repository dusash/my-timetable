/// 界面层共用的一些小工具。
library;

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

/// 1 → 一、7 → 日
String weekdayName(int dayOfWeek) =>
    (dayOfWeek >= 1 && dayOfWeek <= 7) ? _weekdayNames[dayOfWeek - 1] : '?';

/// 1 → 周一
String weekdayFull(int dayOfWeek) => '周${weekdayName(dayOfWeek)}';

/// 7月3日
String shortDate(DateTime date) => '${date.month}月${date.day}日';

/// 10/12
String slashDate(DateTime date) => '${date.month}/${date.day}';

/// 课表网格里位置很窄，把括号里的内容（比如「（1）」「（上）」）去掉，
/// 只留主干名字，这样字大一点也放得下。
String shortCourseName(String name) {
  var result = name;
  for (final pattern in <RegExp>[
    RegExp(r'（[^）]*）'),
    RegExp(r'\([^)]*\)'),
  ]) {
    result = result.replaceAll(pattern, '');
  }
  result = result.trim();
  return result.isEmpty ? name : result;
}

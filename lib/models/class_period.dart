/// 一节「大节」的作息时间。
///
/// 学校里一天分若干大节（第一节、第二节……），每一大节有固定的起止时间。
/// 课表要看时间、算「现在上哪一节」都靠它。
class ClassPeriod {
  /// 第几节，从 1 开始。
  final int node;

  /// 显示名称，例如「第一节」。
  final String label;

  /// 开始时间，HH:mm 格式，例如 08:00。
  final String start;

  /// 结束时间，HH:mm 格式，例如 09:35。
  final String end;

  const ClassPeriod({
    required this.node,
    required this.label,
    required this.start,
    required this.end,
  });

  factory ClassPeriod.fromJson(Map<String, dynamic> json) {
    final node = (json['node'] as num?)?.toInt() ?? 1;
    return ClassPeriod(
      node: node,
      label: json['label'] as String? ?? '第$node节',
      start: json['start'] as String? ?? '',
      end: json['end'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'node': node,
    'label': label,
    'start': start,
    'end': end,
  };

  /// 例如 08:00-09:35；没设置时间时给个友好提示。
  String get range =>
      (start.isEmpty || end.isEmpty) ? '时间待设置' : '$start-$end';

  /// 把 HH:mm 换成当天的第几分钟，方便比较前后顺序。
  static int minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  int get startMinutes => minutesOf(start);
  int get endMinutes => minutesOf(end);

  @override
  String toString() => '$label $range';
}

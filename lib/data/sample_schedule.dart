import 'package:flutter/services.dart' show rootBundle;

import 'schedule_data.dart';

/// 内置示例课表的资源路径（已在 pubspec.yaml 里注册）。
const String kSampleAsset = 'assets/data/sample_schedule.json';

/// 读出内置示例课表，顺便把开学日期校正成「今天那一周再往前数 5 周」。
///
/// 为什么要动开学日期：如果直接把文件里写的日期拿来用，过几个月再点开，
/// 示例就变成了「学期早就结束了」或者「还没开学」，课表一片空白，
/// 用户反而看不出这个 App 能干什么。
/// 校正之后就固定停在**第 6 周**——单周课、双周课、连堂、短期课同时上着，
/// 各种显示效果一次全都能看到。
///
/// 读不到资源时返回 null，让调用方自己决定怎么提示。
Future<ScheduleData?> loadSampleSchedule({DateTime? now}) async {
  final String raw;
  try {
    raw = await rootBundle.loadString(kSampleAsset);
  } on Object {
    return null;
  }

  final sample = ScheduleData.parse(raw);
  final thisMonday = mondayOfDate(now ?? DateTime.now());
  return sample.copyWith(
    semester: sample.semester.copyWith(
      week1Start: thisMonday.subtract(const Duration(days: 5 * 7)),
    ),
  );
}

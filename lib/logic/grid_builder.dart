import '../models/course.dart';
import 'week_calculator.dart';

/// 课表网格里的一个「块」。
///
/// 从第 [startNode] 节开始，连续占 [span] 节。
/// 连堂课（同一天相邻节次、同一门课同一个教室）会合并成一块，
/// 于是在界面上就自然变成一张跨两行的卡片。
class CourseBlock {
  const CourseBlock({
    required this.course,
    required this.startNode,
    required this.span,
    required this.isGhost,
  });

  final Course course;
  final int startNode;
  final int span;

  /// true 表示「本学期有这个安排，但本周不上」，界面显示成灰色。
  final bool isGhost;

  /// 这个块占的最后一个节次。
  int get endNode => startNode + span - 1;

  @override
  String toString() =>
      '${course.courseName} 第$startNode节'
      '${span > 1 ? '-第$endNode节' : ''}'
      '${isGhost ? '（本周不上）' : ''}';
}

/// 算出「某一天的这一周」要在网格里摆哪些块。
///
/// 抽成纯 Dart（不依赖 Flutter）的好处是：可以直接写测试验证，
/// 不用启动手机、也不用启动界面，出问题一眼就能定位。
List<CourseBlock> buildDayBlocks(
  WeekCalculator calculator, {
  required int week,
  required int day,
  required int minNode,
  required int maxNode,
}) {
  // 一、本周确实要上的课
  final activeByNode = <int, Course>{};
  for (final course in calculator.coursesOfDay(week, day)) {
    if (course.node >= minNode && course.node <= maxNode) {
      activeByNode[course.node] = course;
    }
  }

  final blocks = <CourseBlock>[];
  final usedNodes = <int>{};

  var node = minNode;
  while (node <= maxNode) {
    final course = activeByNode[node];
    if (course == null) {
      node++;
      continue;
    }
    // 看看后面紧挨着的节次是不是同一门课（连堂）
    var span = 1;
    while (node + span <= maxNode) {
      final next = activeByNode[node + span];
      if (next == null || !isSameClass(course, next)) break;
      span++;
    }
    for (var i = 0; i < span; i++) {
      usedNodes.add(node + i);
    }
    blocks.add(
      CourseBlock(course: course, startNode: node, span: span, isGhost: false),
    );
    node += span;
  }

  // 二、本学期有这个安排、但本周不上 —— 灰色幽灵卡
  //     （提醒你「这个位置平时是有课的」，比如单周才上的课在双周会显示成灰的）
  for (final course in calculator.courses) {
    if (course.dayOfWeek != day) continue;
    if (course.node < minNode || course.node > maxNode) continue;
    if (usedNodes.contains(course.node)) continue;
    if (course.isActiveInWeek(week)) continue;
    usedNodes.add(course.node);
    blocks.add(
      CourseBlock(
        course: course,
        startNode: course.node,
        span: 1,
        isGhost: true,
      ),
    );
  }

  blocks.sort((a, b) => a.startNode.compareTo(b.startNode));
  return blocks;
}

/// 两条记录是不是「同一节课」（课名、教室、老师都一样）。
bool isSameClass(Course a, Course b) =>
    a.courseName == b.courseName &&
    a.classroom == b.classroom &&
    a.teacher == b.teacher;

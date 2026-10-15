import 'package:flutter/material.dart';

import '../data/schedule_data.dart';
import '../models/course.dart';
import '../models/semester.dart';
import 'course_palette.dart';
import 'ui_helpers.dart';

/// 课表网格里的一张课程卡片。
///
/// 卡片高度由外层的 Positioned 决定（可能是两行），所以这里可以放心用
/// [CrossAxisAlignment.stretch] 让左侧的强调竖条撑满整张卡片。
class CourseBlockCard extends StatelessWidget {
  const CourseBlockCard({
    super.key,
    required this.course,
    required this.palette,
    required this.isGhost,
    required this.span,
    required this.onTap,
  });

  /// 这节课的安排。
  final Course course;

  /// 这门课的颜色（由整份课表统一分配）。
  final CoursePalette palette;

  /// true 表示「本学期有这个安排，但本周不上」，显示成灰色。
  final bool isGhost;

  /// 这张卡片跨了几节（连堂课会 > 1），用来决定课名最多显示几行。
  final int span;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = isGhost ? ghostPalette : this.palette;
    final maxNameLines = span >= 2 ? 4 : 2;

    return Material(
      color: palette.background,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: 3, color: palette.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        shortCourseName(course.courseName),
                        maxLines: maxNameLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    ),
                    if (isGhost)
                      Text(
                        '本周不上',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: palette.text),
                      )
                    else if (course.classroom.isNotEmpty)
                      Text(
                        course.classroom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: palette.text),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 点开课程后的详情弹窗
// ----------------------------------------------------------------------------

/// 弹出课程详情：时间、地点、教师、上课周次，以及本周上不上。
///
/// [onEdit] / [onDelete] 传了才会显示对应的按钮——只读展示时传 null 就行。
Future<void> showCourseDetail(
  BuildContext context, {
  required ScheduleData data,
  required Course course,
  required CoursePalette palette,
  required int week,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final calculator = data.calculator;
  final period = calculator.periodOf(course.node);
  final isActive = course.isActiveInWeek(week);
  final allWeeks = course.weeks;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      course.courseName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.schedule,
                label: '时间',
                value: '${weekdayFull(course.dayOfWeek)} 第${course.node}节'
                    '${period == null ? '' : ' · ${period.range}'}',
              ),
              _InfoRow(
                icon: Icons.place_outlined,
                label: '教室',
                value: course.classroom.isEmpty ? '未填写' : course.classroom,
              ),
              _InfoRow(
                icon: Icons.person_outline,
                label: '教师',
                value: course.teacher.isEmpty ? '未填写' : course.teacher,
              ),
              if (course.courseCode.isNotEmpty)
                _InfoRow(
                  icon: Icons.tag,
                  label: '课程代码',
                  value: course.courseCode,
                ),
              const Divider(height: 26),
              Row(
                children: <Widget>[
                  Text(
                    '上课周次',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    course.ruleText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: <Widget>[
                  for (final w in allWeeks)
                    _WeekChip(week: w, isCurrent: w == week),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? palette.background
                      : Theme.of(sheetContext).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isActive
                      ? '第 $week 周：本周要上这节课'
                      : '第 $week 周：本周不上这节课'
                            '${course.weekRule == WeekRule.every ? '' : '（${Semester.parityLabel(week)}）'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive
                        ? palette.text
                        : Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onEdit != null || onDelete != null) ...<Widget>[
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    if (onEdit != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            onEdit();
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
                        ),
                      ),
                    if (onEdit != null && onDelete != null)
                      const SizedBox(width: 12),
                    if (onDelete != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(sheetContext).colorScheme.error,
                          ),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            onDelete();
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('删除'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({required this.week, required this.isCurrent});

  final int week;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrent
            ? scheme.primary
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$week',
        style: TextStyle(
          fontSize: 12,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          color: isCurrent ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

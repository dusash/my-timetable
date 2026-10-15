import 'package:flutter/material.dart';

import '../models/course.dart';

/// 一门课在界面上的三种颜色：底色、强调色、文字色。
///
/// 直接写死成一组柔和的浅色搭配，而不是用「透明度」现场算，
/// 这样颜色可控、在浅色主题下对比度也够。
class CoursePalette {
  final Color background;
  final Color accent;
  final Color text;

  const CoursePalette({
    required this.background,
    required this.accent,
    required this.text,
  });
}

/// 一共 10 套颜色。比课程门数多几套，同一周里基本不会撞色。
const List<CoursePalette> kCoursePalettes = <CoursePalette>[
  CoursePalette(
    background: Color(0xFFE8F0FB),
    accent: Color(0xFF3F6FB5),
    text: Color(0xFF1E3A63),
  ),
  CoursePalette(
    background: Color(0xFFE3F5F1),
    accent: Color(0xFF2E8B7A),
    text: Color(0xFF14453C),
  ),
  CoursePalette(
    background: Color(0xFFFBEDE7),
    accent: Color(0xFFC1603A),
    text: Color(0xFF6B2F16),
  ),
  CoursePalette(
    background: Color(0xFFF0EAFB),
    accent: Color(0xFF7A5AA8),
    text: Color(0xFF3D2B57),
  ),
  CoursePalette(
    background: Color(0xFFFAF2DC),
    accent: Color(0xFF9C7A1E),
    text: Color(0xFF4E3D0E),
  ),
  CoursePalette(
    background: Color(0xFFE6F2F8),
    accent: Color(0xFF2F7FA8),
    text: Color(0xFF16404F),
  ),
  CoursePalette(
    background: Color(0xFFFBE9EF),
    accent: Color(0xFFB8435F),
    text: Color(0xFF5C1F2E),
  ),
  CoursePalette(
    background: Color(0xFFEDF4E6),
    accent: Color(0xFF5C8438),
    text: Color(0xFF2D4218),
  ),
  CoursePalette(
    background: Color(0xFFF5EDE4),
    accent: Color(0xFF8A6134),
    text: Color(0xFF4A3418),
  ),
  CoursePalette(
    background: Color(0xFFECEEF2),
    accent: Color(0xFF5C6B84),
    text: Color(0xFF2E3949),
  ),
];

/// 本周不上课的课，统一用灰色，一眼就能和「要上的课」区分开。
const CoursePalette ghostPalette = CoursePalette(
  background: Color(0xFFF1EFE8),
  accent: Color(0xFFB4B2A9),
  text: Color(0xFF6B6960),
);

/// 第 [index] 套配色（会绕圈，所以不会越界）。
CoursePalette paletteAt(int index) =>
    kCoursePalettes[index % kCoursePalettes.length];

/// 给整份课表里的每门课安排一个固定颜色。
///
/// 按「第一次出现的顺序」依次分配，而不是用课名做哈希——哈希难免撞色，
/// 而顺序分配能保证一学期里每门课颜色都不重样。同一门课在任何地方都用同一个颜色。
Map<String, CoursePalette> buildCoursePaletteMap(List<Course> courses) {
  final result = <String, CoursePalette>{};
  for (final course in courses) {
    if (result.containsKey(course.courseName)) continue;
    result[course.courseName] = paletteAt(result.length);
  }
  return result;
}

/// 取颜色，取不到就给第一套（正常不会发生）。
CoursePalette paletteOf(Map<String, CoursePalette> map, String courseName) =>
    map[courseName] ?? kCoursePalettes.first;

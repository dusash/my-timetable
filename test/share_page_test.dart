// 分享页的自动化测试。
//
// 两条链路都要走通：
//   ① 把我的课表编成码、显示出来；
//   ② 把同学发来的码（或一段课表文字）粘进来、认出来、导进来。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_store.dart';
import 'package:my_timetable/logic/share_code.dart';
import 'package:my_timetable/models/course.dart';
import 'package:my_timetable/state/schedule_controller.dart';
import 'package:my_timetable/ui/share_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 页面最外层那个可滚动列表。
/// TabBarView 里两个标签页各有一个 ListView，取最后构建的那个（当前可见的）。
Finder get pageScrollable => find.byType(Scrollable).last;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200, scrollable: pageScrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ScheduleController> pumpShare(WidgetTester tester) async {
  usePhoneSurface(tester);

  final controller = ScheduleController(
    repository: ScheduleRepository(
      store: MemoryScheduleStore(),
      seedJson: File('assets/data/sample_schedule.json').readAsStringSync(),
    ),
  );
  await controller.load();

  await tester.pumpWidget(MaterialApp(home: SharePage(controller: controller)));
  await tester.pumpAndSettle();
  return controller;
}

/// 切到「导入课表」这一页。
Future<void> openImportTab(WidgetTester tester) async {
  await tester.tap(find.text('导入课表'));
  await tester.pumpAndSettle();
}

/// 页面上是不是真的显示了以 KTB1 开头的分享码。
/// （分享码放在 SelectableText 里，方便长按选中复制。）
bool showsCode(WidgetTester tester, String code) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .any((s) => s.data == code);

void main() {
  group('分享给同学', () {
    testWidgets('打开分享页没有布局报错', (tester) async {
      await pumpShare(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('课表概览、二维码、分享码都在', (tester) async {
      final controller = await pumpShare(tester);

      expect(find.text('分享给同学'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);

      final names = controller.data!.courses.map((c) => c.courseName).toSet();
      expect(find.textContaining('${names.length} 门课'), findsWidgets);

      expect(showsCode(tester, ShareCode.encode(controller.data!)), isTrue);
    });

    testWidgets('课表变了之后，分享码会跟着更新', (tester) async {
      final controller = await pumpShare(tester);
      final before = ShareCode.encode(controller.data!);
      expect(showsCode(tester, before), isTrue);

      await controller.replaceAll(
        controller.data!.copyWith(
          courses: controller.data!.courses.take(3).toList(),
        ),
      );

      // 重新构建页面（相当于用户退出再进来）
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: SharePage(controller: controller)));
      await tester.pumpAndSettle();

      expect(showsCode(tester, before), isFalse);
      expect(showsCode(tester, ShareCode.encode(controller.data!)), isTrue);
    });
  });

  group('导入：同学发来的分享码', () {
    testWidgets('粘进来能认出是分享码，并给出预览', (tester) async {
      final controller = await pumpShare(tester);
      await openImportTab(tester);

      await tester.enterText(
        find.byType(TextField),
        ShareCode.encode(controller.data!),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));

      expect(find.text('认出这是一份课表分享码'), findsOneWidget);
      expect(find.textContaining('这是一份完整的课表'), findsOneWidget);
    });

    testWidgets('合并自己那份课表：一条都不多、也不报错', (tester) async {
      final controller = await pumpShare(tester);
      final before = controller.data!.courses.length;

      await openImportTab(tester);
      await tester.enterText(
        find.byType(TextField),
        ShareCode.encode(controller.data!),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));
      await tapVisible(tester, find.textContaining('合并进我的课表'));

      expect(controller.data!.courses.length, before);
      expect(find.textContaining('跳过'), findsOneWidget);
    });

    testWidgets('合并一份只有新课的分享码，数量增加', (tester) async {
      final controller = await pumpShare(tester);
      final before = controller.data!.courses.length;

      final friend = controller.data!.copyWith(
        courses: <Course>[
          Course(
            id: 'friend1',
            courseName: '人工智能导论',
            teacher: '王老师',
            courseCode: '',
            dayOfWeek: 5,
            node: 3,
            weekRule: WeekRule.every,
            startWeek: 1,
            endWeek: 16,
            classroom: '教5-201',
          ),
        ],
      );

      await openImportTab(tester);
      await tester.enterText(find.byType(TextField), ShareCode.encode(friend));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));
      await tapVisible(tester, find.textContaining('合并进我的课表'));

      expect(controller.data!.courses.length, before + 1);
      expect(
        controller.data!.courses.any((c) => c.courseName == '人工智能导论'),
        isTrue,
      );
      expect(find.textContaining('已导入'), findsOneWidget);
    });

    testWidgets('整份替换要先确认，确认后只剩同学那一份', (tester) async {
      final controller = await pumpShare(tester);

      final friend = controller.data!.copyWith(
        courses: <Course>[
          Course(
            id: 'friend1',
            courseName: '人工智能导论',
            teacher: '',
            courseCode: '',
            dayOfWeek: 5,
            node: 3,
            weekRule: WeekRule.every,
            startWeek: 1,
            endWeek: 16,
          ),
        ],
      );

      await openImportTab(tester);
      await tester.enterText(find.byType(TextField), ShareCode.encode(friend));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));

      await tapVisible(tester, find.textContaining('整份替换'));
      expect(find.text('用这份课表替换现在的？'), findsOneWidget);

      // 先点取消：什么都不该发生
      await tapVisible(tester, find.text('取消'));
      expect(
        controller.data!.courses.any((c) => c.courseName == '人工智能导论'),
        isFalse,
      );

      // 再来一次，这次确认
      await tapVisible(tester, find.textContaining('整份替换'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '替换'));

      expect(controller.data!.courses.length, 1);
      expect(controller.data!.courses.single.courseName, '人工智能导论');
      expect(find.textContaining('已替换'), findsOneWidget);
    });

    testWidgets('乱粘一段话会提示认不出来', (tester) async {
      await pumpShare(tester);
      await openImportTab(tester);

      await tester.enterText(find.byType(TextField), '今天晚上吃什么好呢');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));

      expect(find.textContaining('没能从这段文字里认出课程'), findsOneWidget);
    });

    testWidgets('空着就点识别会提示先粘贴', (tester) async {
      await pumpShare(tester);
      await openImportTab(tester);

      await tapVisible(tester, find.text('识别一下'));
      expect(find.textContaining('先把同学发来的分享码粘贴进来'), findsOneWidget);
    });
  });

  group('导入：教务系统复制的文本', () {
    const timetableText = '''
高等数学B（上） 周一 第1-2节 3-15周 教5-201 张三
大学英语读写（1） 周四 第2节 3-17周(单) 东12-301 李四
大学英语视听说（1） 周四 第2节 4-18周(双) 东12-301 李四
''';

    testWidgets('粘一段课表文字，能认出课程并给出预览', (tester) async {
      await pumpShare(tester);
      await openImportTab(tester);

      await tester.enterText(find.byType(TextField), timetableText);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));

      expect(find.text('从文字里认出了课表'), findsOneWidget);
      // 3 门课（高等数学 + 英语读写 + 英语视听说）
      // 4 条安排（高等数学连堂 2 条 + 单双周各 1 条）
      expect(find.textContaining('3 门课'), findsOneWidget);
      expect(find.textContaining('4 条安排'), findsOneWidget);
    });

    testWidgets('文本导入之后，课表里真的有这些课', (tester) async {
      final controller = await pumpShare(tester);
      await openImportTab(tester);

      await tester.enterText(find.byType(TextField), timetableText);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));
      await tapVisible(tester, find.textContaining('整份替换'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '替换'));

      final names = controller.data!.courses.map((c) => c.courseName).toSet();
      expect(names, contains('高等数学B（上）'));
      expect(names, contains('大学英语读写（1）'));
      expect(controller.data!.courses.length, 4);
    });

    testWidgets('改一下输入框，旧的预览会自动收起来', (tester) async {
      await pumpShare(tester);
      await openImportTab(tester);

      await tester.enterText(find.byType(TextField), timetableText);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('识别一下'));
      expect(find.text('从文字里认出了课表'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        '$timetableText\n体育 周三 第5节 1-16周 田径场',
      );
      await tester.pumpAndSettle();

      expect(find.text('从文字里认出了课表'), findsNothing);
    });
  });
}

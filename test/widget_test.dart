// 阶段 2 界面的自动化测试：把课表网格真正画出来，检查它画对了、也没报错。
//
// 运行： flutter test
//
// 这里的测试很值钱：Flutter 的「布局溢出」「控件没量出尺寸」这类问题
// 在测试里会直接报错，所以它能帮我们在装到手机之前就发现界面 bug。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_timetable/data/schedule_data.dart';
import 'package:my_timetable/ui/course_card.dart';
import 'package:my_timetable/ui/week_grid_page.dart';

ScheduleData loadData() =>
    ScheduleData.parse(File('assets/data/sample_schedule.json').readAsStringSync());

/// 把当前画出来的所有课程卡片里，课名含 [key] 的那些挑出来。
///
/// 为什么要这样写：同一门课一周可能上两次（比如「大学英语读写（1）」
/// 周二第一节和周四第二节都有），所以不能用「全屏幕搜文字」的方式判断
/// 某节课上不上 —— 必须连「星期几 + 第几节」一起看。
Iterable<CourseBlockCard> cardsNamed(WidgetTester tester, String key) => tester
    .widgetList<CourseBlockCard>(find.byType(CourseBlockCard))
    .where((card) => card.course.courseName.contains(key));

/// 判断「星期 [day] 的第 [node] 节」这一格上画的是不是课名含 [key] 的课。
bool hasCardAt(WidgetTester tester, String key, int day, int node) =>
    cardsNamed(tester, key).any(
      (card) => card.course.dayOfWeek == day && card.course.node == node,
    );

/// 一个「会自己保存」的课表页外壳。
///
/// 真实 App 里是「控制器改数据 → 页面重画」，这里用一个 StatefulWidget
/// 把这套回路复刻出来，于是测试可以完整地走一遍「点添加 → 填表 → 保存」。
class EditableHost extends StatefulWidget {
  const EditableHost({
    super.key,
    required this.initial,
    this.now,
    this.onLoadSample,
    this.onOpenImport,
  });

  final ScheduleData initial;
  final DateTime? now;

  /// 空课表页上多出来的两个入口，真实 App 里由 main.dart 接上。
  final VoidCallback? onLoadSample;
  final VoidCallback? onOpenImport;

  @override
  State<EditableHost> createState() => EditableHostState();
}

class EditableHostState extends State<EditableHost> {
  late ScheduleData data = widget.initial;

  /// 课表被改了几次，用来断言「该保存的保存了、不该动的没动」。
  int changeCount = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WeekGridPage(
        data: data,
        now: widget.now,
        onDataChanged: (next) {
          setState(() {
            data = next;
            changeCount++;
          });
        },
        onLoadSample: widget.onLoadSample,
        onOpenImport: widget.onOpenImport,
        onOpenSettings: () {},
      ),
    );
  }
}

/// 可编辑模式下的课表页。返回外壳，方便测试检查内部数据。
Future<EditableHostState> pumpEditable(
  WidgetTester tester,
  DateTime now, {
  ScheduleData? data,
  VoidCallback? onLoadSample,
  VoidCallback? onOpenImport,
}) async {
  usePhoneSurface(tester);
  final key = GlobalKey<EditableHostState>();
  await tester.pumpWidget(
    EditableHost(
      key: key,
      initial: data ?? loadData(),
      now: now,
      onLoadSample: onLoadSample,
      onOpenImport: onOpenImport,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 一份「刚装好 App」的空课表，开学日期固定，方便复现。
ScheduleData emptyData() =>
    ScheduleData.empty(week1Start: DateTime(2026, 9, 7));

/// 把测试窗口设成手机大小（360 × 780 逻辑像素）。
///
/// flutter_test 默认给的是 800×600，相当于一个横屏小平板：
/// 课表会挤成奇怪的比例，弹窗底部的按钮还会被推到屏幕外点不中。
/// 改成手机尺寸后，测出来的东西才和真机一致。
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 先滚到能看见，再点击。
///
/// 弹窗和长表单在小屏幕上会有内容在折叠线以下，
/// 直接 tap 会报「widget is off-screen」，这个函数能一劳永逸地解决。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 用指定的「今天」把课表网格搭起来，这样测试结果和运行日期无关。
Future<void> pumpGrid(WidgetTester tester, DateTime now) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(home: WeekGridPage(data: loadData(), now: now)),
  );
  await tester.pumpAndSettle();
}

void main() {
  // 2026-10-15 是第 6 周（双周）的周四
  final week6Thursday = DateTime(2026, 10, 15);
  // 2026-10-08 是第 5 周（单周）的周四
  final week5Thursday = DateTime(2026, 10, 8);
  // 2026-12-03 是第 13 周（单周）的周四
  final week13Thursday = DateTime(2026, 12, 3);

  testWidgets('网格能正常渲染，没有任何布局报错', (tester) async {
    await pumpGrid(tester, week6Thursday);

    expect(tester.takeException(), isNull);
    expect(find.text('节次'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周五'), findsOneWidget);
  });

  testWidgets('默认只显示周一到周五，点右上角可以切出周末', (tester) async {
    await pumpGrid(tester, week6Thursday);

    expect(find.text('周六'), findsNothing);
    expect(find.text('周日'), findsNothing);

    await tester.tap(find.byIcon(Icons.filter_7_outlined));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('周六'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
  });

  testWidgets('双周的第 6 周：周四第二节显示视听说，不显示读写', (tester) async {
    await pumpGrid(tester, week6Thursday);

    // 周四 = 第 4 天，第二节 = node 2
    expect(hasCardAt(tester, '大学英语视听说', 4, 2), isTrue);
    expect(hasCardAt(tester, '大学英语读写', 4, 2), isFalse);
  });

  testWidgets('单周的第 5 周：周四第二节换成读写，视听说消失', (tester) async {
    await pumpGrid(tester, week5Thursday);

    expect(hasCardAt(tester, '大学英语读写', 4, 2), isTrue);
    expect(hasCardAt(tester, '大学英语视听说', 4, 2), isFalse);
  });

  testWidgets('第 6 周周五第四节是心理教育健康', (tester) async {
    await pumpGrid(tester, week6Thursday);

    // 周五 = 第 5 天，第四节 = node 4
    expect(hasCardAt(tester, '心理教育健康', 5, 4), isTrue);
    expect(hasCardAt(tester, '职业发展', 5, 4), isFalse);
  });

  testWidgets('第 13 周周五第四节换成职业发展', (tester) async {
    await pumpGrid(tester, week13Thursday);

    expect(hasCardAt(tester, '职业发展', 5, 4), isTrue);
    expect(hasCardAt(tester, '心理教育健康', 5, 4), isFalse);
  });

  testWidgets('本周不上的课显示成灰色幽灵卡（第 6 周有 2 个）', (tester) async {
    await pumpGrid(tester, week6Thursday);

    // 人文素质教育（单周）和形势与政策（第 9-12 周）本周都不上
    expect(find.text('本周不上'), findsNWidgets(2));
  });

  testWidgets('点课程卡片弹出详情，能看到上课周次', (tester) async {
    await pumpGrid(tester, week6Thursday);

    await tester.tap(find.text('高等数学B').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('上课周次'), findsOneWidget);
    expect(find.textContaining('本周要上这节课'), findsOneWidget);
    expect(find.textContaining('李明'), findsWidgets);
  });

  testWidgets('点左右箭头可以切换周次', (tester) async {
    await pumpGrid(tester, week6Thursday);

    String weekTitle() {
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data ?? '';
        if (data.contains('周 · ')) return data;
      }
      return '';
    }

    final before = weekTitle();
    expect(before, contains('第 6 周'));
    expect(before, contains('双周'));

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    final after = weekTitle();
    expect(after, contains('第 5 周'));
    expect(after, contains('单周'));

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(weekTitle(), before);
  });

  // ==========================================================================
  // 阶段 3：可编辑模式的界面测试
  // ==========================================================================

  group('只读 vs 可编辑', () {
    testWidgets('只读模式（不传 onDataChanged）没有添加按钮，也没有设置入口', (tester) async {
      await pumpGrid(tester, week6Thursday);

      expect(find.text('添加课程'), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('可编辑模式才有添加按钮', (tester) async {
      await pumpEditable(tester, week6Thursday);

      expect(find.text('添加课程'), findsOneWidget);
      expect(find.text('添加第一门课'), findsNothing);
    });
  });

  group('添加课程', () {
    testWidgets('点「添加课程」能打开表单', (tester) async {
      await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      expect(find.text('保存这门课'), findsOneWidget);
      expect(find.text('课程名称 *'), findsOneWidget);
    });

    testWidgets('填一门周六的新课并保存，周末视图里能看到它', (tester) async {
      final host = await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '人工智能导论');
      await tester.pumpAndSettle();

      // 星期改成周六
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('周六').last);
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('保存这门课'));
      await tester.pumpAndSettle();

      // 表单关掉，回到课表，并且数据真的交出去了
      expect(find.text('保存这门课'), findsNothing);
      expect(host.changeCount, 1);
      expect(
        host.data.courses.any((c) => c.courseName == '人工智能导论'),
        isTrue,
      );

      // 打开周末视图，新课出现在周六第一节
      await tester.tap(find.byIcon(Icons.filter_7_outlined));
      await tester.pumpAndSettle();

      expect(hasCardAt(tester, '人工智能导论', 6, 1), isTrue);
    });

    testWidgets('和已有课程撞格子时会先提醒，选「回去改」则不保存', (tester) async {
      final host = await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '抢占高数的课');
      await tester.pumpAndSettle();

      // 默认就是周一第一节，那里已经有高等数学B了
      await tapVisible(tester, find.text('保存这门课'));
      await tester.pumpAndSettle();

      expect(find.text('这一格已经有课了'), findsOneWidget);

      await tester.tap(find.text('回去改'));
      await tester.pumpAndSettle();

      expect(host.changeCount, 0, reason: '没有确认就不该改动课表');
      expect(find.text('保存这门课'), findsOneWidget, reason: '应该还停在表单上');
    });

    testWidgets('点了「仍然保存」就真的存下来', (tester) async {
      final host = await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('添加课程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '抢占高数的课');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('保存这门课'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('仍然保存'));
      await tester.pumpAndSettle();

      expect(host.changeCount, 1);
      expect(
        host.data.courses.any((c) => c.courseName == '抢占高数的课'),
        isTrue,
      );
    });
  });

  group('编辑与删除', () {
    testWidgets('可编辑模式下，详情弹窗里有「编辑」和「删除」', (tester) async {
      await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('高等数学B').first);
      await tester.pumpAndSettle();

      expect(find.text('上课周次'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '编辑'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '删除'), findsOneWidget);
    });

    testWidgets('只读模式下详情弹窗里没有编辑 / 删除', (tester) async {
      await pumpGrid(tester, week6Thursday);

      await tester.tap(find.text('高等数学B').first);
      await tester.pumpAndSettle();

      expect(find.text('上课周次'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '编辑'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '删除'), findsNothing);
    });

    testWidgets('点「编辑」能打开表单，并且已经填好了原来那门课', (tester) async {
      await pumpEditable(tester, week6Thursday);

      await tester.tap(find.text('高等数学B').first);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, '编辑'));
      await tester.pumpAndSettle();

      expect(find.text('编辑课程'), findsOneWidget);
      expect(find.text('高等数学B（上）'), findsOneWidget);
    });

    testWidgets('删除一门课之后，课表里就少了一张它的卡片', (tester) async {
      final host = await pumpEditable(tester, week6Thursday);

      final matching = tester
          .widgetList<CourseBlockCard>(find.byType(CourseBlockCard))
          .where((c) => c.course.courseName.contains('高等数学B'))
          .toList();
      expect(matching, isNotEmpty);

      // 注意：同一门课一周可能上三次（这里是周一、周三、周五），
      // 在数据里就是三条独立记录，所以必须按 id 判断，不能按课名判断。
      final targetId = matching.first.course.id;
      final before = host.data.courses.length;

      await tester.tap(find.text('高等数学B').first);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(OutlinedButton, '删除'));
      await tester.pumpAndSettle();

      // 二次确认
      expect(find.textContaining('删除「'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已删除'), findsOneWidget);
      expect(host.data.courses.length, before - 1);
      expect(host.data.courses.any((c) => c.id == targetId), isFalse);
    });

    testWidgets('删错了可以点「撤销」找回来', (tester) async {
      final host = await pumpEditable(tester, week6Thursday);

      final targetId = tester
          .widgetList<CourseBlockCard>(find.byType(CourseBlockCard))
          .firstWhere((c) => c.course.courseName.contains('高等数学B'))
          .course
          .id;
      final before = host.data.courses.length;

      await tester.tap(find.text('高等数学B').first);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(OutlinedButton, '删除'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(host.data.courses.any((c) => c.id == targetId), isFalse);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(host.data.courses.length, before);
      expect(host.data.courses.any((c) => c.id == targetId), isTrue);
    });
  });

  group('空课表', () {
    testWidgets('一门课都没有时显示引导页', (tester) async {
      await pumpEditable(tester, week6Thursday, data: emptyData());

      expect(find.text('还没有课程'), findsOneWidget);
      expect(find.text('添加第一门课'), findsOneWidget);
      // 空课表不应该再画网格表头
      expect(find.text('节次'), findsNothing);
    });

    testWidgets('出厂状态的第一屏给出三条路：自己录、导入、看示例', (tester) async {
      await pumpEditable(
        tester,
        week6Thursday,
        data: emptyData(),
        onLoadSample: () {},
        onOpenImport: () {},
      );

      expect(find.text('添加第一门课'), findsOneWidget);
      expect(find.text('从教务系统导入'), findsOneWidget);
      expect(find.text('先看看示例课表'), findsOneWidget);
    });

    testWidgets('点「先看看示例课表」会通知上层去装示例', (tester) async {
      var tapped = 0;
      await pumpEditable(
        tester,
        week6Thursday,
        data: emptyData(),
        onLoadSample: () => tapped++,
      );

      await tapVisible(tester, find.text('先看看示例课表'));
      expect(tapped, 1);
    });

    testWidgets('点「从教务系统导入」会通知上层打开导入页', (tester) async {
      var tapped = 0;
      await pumpEditable(
        tester,
        week6Thursday,
        data: emptyData(),
        onOpenImport: () => tapped++,
      );

      await tapVisible(tester, find.text('从教务系统导入'));
      expect(tapped, 1);
    });

    testWidgets('上层没接这两个入口时，它们就不出现（只读场景）', (tester) async {
      await pumpEditable(tester, week6Thursday, data: emptyData());

      expect(find.text('从教务系统导入'), findsNothing);
      expect(find.text('先看看示例课表'), findsNothing);
      // 但「添加第一门课」还在，因为这是可编辑模式
      expect(find.text('添加第一门课'), findsOneWidget);
    });
  });
}

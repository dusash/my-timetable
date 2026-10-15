import 'dart:convert';
import 'dart:io' show gzip;

import '../models/class_period.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../data/schedule_data.dart';

// ============================================================================
// 分享码：把一整份课表变成一段可以复制粘贴的短文本。
//
// 为什么要压缩：一份课表的 JSON 大约 4.5 KB，直接发出去太长，
// 微信里发、手动抄、塞进二维码都费劲。所以流程是：
//
//     课表 → 精简成短字段 JSON → gzip 压缩 → Base64 编码 → 「KTB1:xxxx」
//
// 压缩后通常只剩 1 KB 左右，二维码装得下（二维码最多约 2.9 KB）。
//
// 整个过程完全在本机完成：不联网、不传服务器、不需要账号。
// 分享码本身就是数据，你复制给谁，谁就能导入。
// ============================================================================

/// 分享码的固定开头。看到它就说明这是「我的课表」的分享码。
const String kShareCodePrefix = 'KTB1';

/// 分享码当前的格式版本。以后格式变了可以靠它做兼容。
const int kShareCodeVersion = 1;

/// 分享码里的内容超出二维码容量时，只给文本复制、不画二维码。
///
/// 二维码在最低纠错等级下最多装约 2953 字节（二进制模式），
/// 留一点余量，避免算出图来扫不出。
const int kMaxQrPayloadLength = 2800;

/// 分享码解析失败时抛出的异常，[message] 是可以直接给用户看的中文。
class ShareCodeException implements Exception {
  const ShareCodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 分享码的编码 / 解码。
///
/// 全是静态方法，不需要创建对象——它只是「数据 ↔ 文本」的一层转接。
class ShareCode {
  const ShareCode._();

  // ------------------------------------------------------------------ 编码

  /// 把一份课表编成分享码。
  static String encode(ScheduleData data) {
    final compact = _toCompact(data);
    final raw = utf8.encode(jsonEncode(compact));
    // gzip 里带了 CRC 校验，传输过程中被改动过的话解压时会报错，
    // 这样我们就能给用户「码不完整」这种准确的提示，而不是莫名其妙地导入半份课表。
    final packed = gzip.encode(raw);
    final body = base64Url.encode(packed).replaceAll('=', '');
    return '$kShareCodePrefix:$body';
  }

  /// 分享码里数据部分的长短（越短越好扫）。
  static int payloadLength(String code) {
    final body = _stripToBody(code);
    return body.length;
  }

  /// 这份分享码能不能画成二维码。
  static bool fitsInQrCode(String code) =>
      payloadLength(code) <= kMaxQrPayloadLength;

  // ------------------------------------------------------------------ 解码

  /// 把分享码解回课表。
  ///
  /// 会主动容忍这些「复制粘贴带来的小问题」：
  ///   · 前后多出来的空格、换行、聊天软件加的空格；
  ///   · 前缀写成全角冒号「KTB1：」；
  ///   · 前面带着「分享码：」这类说明文字（只认 KTB1 之后的内容）。
  ///
  /// 实在认不出来就抛 [ShareCodeException]，里面的中文可以直接显示给用户。
  static ScheduleData decode(String input) {
    final text = input.replaceAll(RegExp(r'\s'), '');
    if (text.isEmpty) {
      throw const ShareCodeException('还没有粘贴任何内容');
    }

    final body = _stripToBody(text);
    if (body.isEmpty) {
      throw const ShareCodeException('这看起来不是一份课表分享码');
    }

    final List<int> packed;
    try {
      packed = base64Url.decode(_padBase64(body));
    } on Object {
      throw const ShareCodeException(
        '分享码不完整，可能只复制了一部分，让同学重新发一次',
      );
    }

    final List<int> raw;
    try {
      raw = gzip.decode(packed);
    } on Object {
      throw const ShareCodeException('分享码内容已损坏，让同学重新发一次吧');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on Object {
      throw const ShareCodeException('分享码内容已损坏，让同学重新发一次吧');
    }

    if (decoded is! Map) {
      throw const ShareCodeException('分享码内容已损坏，让同学重新发一次吧');
    }

    return _fromCompact(Map<String, dynamic>.from(decoded));
  }

  /// 从一段可能混着说明文字的文本里，截出分享码的数据部分。
  static String _stripToBody(String text) {
    final index = text.indexOf(kShareCodePrefix);
    if (index < 0) {
      // 没有前缀时，把整段都当数据，但要先把不像 Base64 的字符去掉。
      return _keepBase64Chars(text);
    }

    var body = text.substring(index + kShareCodePrefix.length);
    // 前缀后面可能跟半角或全角冒号，还有可能什么都不跟。
    body = body.replaceFirst(RegExp(r'^[:：]'), '');
    return _keepBase64Chars(body);
  }

  /// 只留下 Base64 里合法的字符。
  ///
  /// 这一步是为了对付「同学把分享码夹在一句话里发过来」这种情况：
  /// 前面写着「我的课表给你：」，后面跟着「收到回我一下」，
  /// 这些中文字符如果不剔掉，整段 Base64 就解不开了。
  static String _keepBase64Chars(String body) =>
      body.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');

  /// Base64 去掉填充后，解码前要把「=」补回来。
  static String _padBase64(String body) {
    final remainder = body.length % 4;
    if (remainder == 0) return body;
    return body + '=' * (4 - remainder);
  }

  // -------------------------------------------------------- 精简格式的读写

  /// 转成「按键位排列」的短格式。
  ///
  /// 用数组代替一个个字段名，是因为 `"courseName"` 这种键名本身就要占十几个字节，
  /// 几十门课累积下来非常可观。反正格式由我们自己读写，不需要给人看。
  static Map<String, dynamic> _toCompact(ScheduleData data) {
    return <String, dynamic>{
      'v': kShareCodeVersion,
      'c': data.campus,
      's': <dynamic>[
        data.semester.name,
        Semester.formatDate(data.semester.week1Start),
        data.semester.totalWeeks,
      ],
      'p': data.periods
          .map((p) => <dynamic>[p.node, p.start, p.end])
          .toList(growable: false),
      'k': data.courses
          .map(
            (c) => <dynamic>[
              c.courseName,
              c.teacher,
              c.courseCode,
              c.dayOfWeek,
              c.node,
              c.weekRule.code,
              c.startWeek,
              c.endWeek,
              c.customWeeks,
              c.classroom,
              c.overrides.map((k, v) => MapEntry(k.toString(), v)),
            ],
          )
          .toList(growable: false),
    };
  }

  /// 把短格式还原成课表对象。
  static ScheduleData _fromCompact(Map<String, dynamic> json) {
    // 必须是我们自己写的那几个字段，否则说明这段码是别的东西。
    // 注意「空课表」是合法的（k 和 s 都在，只是内容是空的），
    // 所以这里只检查字段在不在，不检查内容多少。
    if (json['v'] == null || json['k'] == null || json['s'] == null) {
      throw const ShareCodeException('这看起来不是一份课表分享码');
    }

    final version = (json['v'] as num?)?.toInt() ?? 0;
    if (version > kShareCodeVersion) {
      throw ShareCodeException(
        '这份分享码来自更新版本的 App（v$version），'
        '请升级到最新版再导入',
      );
    }

    final semesterRaw = json['s'];
    final semester = semesterRaw is List && semesterRaw.length >= 3
        ? Semester(
            name: '${semesterRaw[0]}',
            week1Start:
                DateTime.tryParse('${semesterRaw[1]}') ?? DateTime.now(),
            totalWeeks: _asInt(semesterRaw[2], fallback: 20),
          )
        : Semester(name: '我的学期', week1Start: DateTime.now(), totalWeeks: 20);

    final periods = <ClassPeriod>[];
    final rawPeriods = json['p'];
    if (rawPeriods is List) {
      for (final item in rawPeriods) {
        if (item is List && item.isNotEmpty) {
          final node = _asInt(item[0], fallback: 1);
          periods.add(
            ClassPeriod(
              node: node,
              label: '第$node节',
              start: item.length > 1 ? '${item[1]}' : '',
              end: item.length > 2 ? '${item[2]}' : '',
            ),
          );
        }
      }
    }
    periods.sort((a, b) => a.node.compareTo(b.node));

    final courses = <Course>[];
    final rawCourses = json['k'];
    if (rawCourses is List) {
      for (var i = 0; i < rawCourses.length; i++) {
        final item = rawCourses[i];
        if (item is! List || item.length < 8) continue;

        final customWeeks = <int>[];
        if (item.length > 8 && item[8] is List) {
          for (final w in item[8] as List) {
            if (w is num) customWeeks.add(w.toInt());
          }
        }

        final overrides = <int, bool>{};
        if (item.length > 10 && item[10] is Map) {
          (item[10] as Map).forEach((key, value) {
            final week = int.tryParse('$key');
            if (week != null && value is bool) overrides[week] = value;
          });
        }

        courses.add(
          Course(
            // 分享码里不带 id：id 是每台手机自己生成的，带过来反而可能撞车。
            // 真正入库时会重新编号。
            id: 'shared${i + 1}',
            courseName: '${item[0]}',
            teacher: item.length > 1 ? '${item[1]}' : '',
            courseCode: item.length > 2 ? '${item[2]}' : '',
            dayOfWeek: _asInt(item[3], fallback: 1),
            node: _asInt(item[4], fallback: 1),
            weekRule: WeekRule.fromCode(item.length > 5 ? '${item[5]}' : null),
            startWeek: _asInt(item[6], fallback: 1),
            endWeek: _asInt(item[7], fallback: 1),
            customWeeks: customWeeks,
            classroom: item.length > 9 ? '${item[9]}' : '',
            overrides: overrides,
          ),
        );
      }
    }

    return ScheduleData(
      campus: '${json['c'] ?? ''}',
      semester: semester,
      periods: periods,
      courses: courses,
    );
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}

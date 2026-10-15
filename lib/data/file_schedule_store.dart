import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'schedule_store.dart';

/// 把课表存成手机里的一个 JSON 文件：`<App 私有目录>/schedule.json`。
///
/// 为什么用 App 私有目录（而不是公共存储）：
///   · 不需要申请任何存储权限，装完就能用；
///   · 别的 App 看不到，安全；
///   · 卸载 App 时一起删掉，不会在你手机里留垃圾。
class FileScheduleStore implements ScheduleStore {
  FileScheduleStore({this.fileName = 'schedule.json'});

  /// 文件名。写测试时可以换成别的名字。
  final String fileName;

  File? _cached;

  Future<File> _file() async {
    final cached = _cached;
    if (cached != null) return cached;

    final dir = await getApplicationDocumentsDirectory();
    return _cached = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String text) async {
    final file = await _file();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    // 先写到临时文件，再改名覆盖。
    // 这样万一写到一半没电 / 被系统杀掉，原来的课表也不会变成半截乱码。
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}

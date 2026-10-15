import 'schedule_data.dart';

// ============================================================================
// 课表「存到哪儿、从哪儿读」的唯一入口。
//
// 这里刻意不依赖 Flutter、也不依赖文件系统：只认一个 [ScheduleStore] 接口。
// 于是：
//   · 手机上跑 → 传 FileScheduleStore（存成一个 JSON 文件）
//   · 写测试时 → 传 MemoryScheduleStore（只放内存，不留垃圾）
//   · 以后做「同学分享码」→ 再写一个 Store 就行，这个文件不用改
// ============================================================================

/// 一段课表文本的存取方式。
abstract class ScheduleStore {
  /// 读出已保存的课表文本；从没存过就返回 null。
  Future<String?> read();

  /// 把课表文本写进去（整份覆盖）。
  Future<void> write(String text);

  /// 删掉已保存的内容（恢复出厂时会用到）。
  Future<void> clear();
}

/// 只放在内存里的实现，专门给测试用。
class MemoryScheduleStore implements ScheduleStore {
  MemoryScheduleStore([this._text]);

  String? _text;

  /// 当前存着的内容，方便测试里直接断言。
  String? get text => _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async {
    _text = text;
  }

  @override
  Future<void> clear() async {
    _text = null;
  }
}

/// 课表仓库：把「数据从哪来」这件事收在一个地方。
class ScheduleRepository {
  ScheduleRepository({required this.store, this.seedJson});

  /// 真正负责存取的实现。
  final ScheduleStore store;

  /// 可选的「首批数据」。
  ///
  /// 正式 App **不传**这个参数 —— 出厂就是一份干净的空课表，用户自己录。
  /// 它主要给测试用，方便造一个「本机还没有存档」的场景。
  final String? seedJson;

  /// 读取课表。
  ///
  /// 顺序是：
  ///   1. 本机已经保存过的 → 直接用（用户的修改永远优先）；
  ///   2. 没有保存过 → 这是第一次打开 App，给一份空课表并顺手存下来；
  ///   3. 存档存在但读坏了 → 也返回空课表，但**故意不覆盖**那个坏文件，
  ///      万一还能手工抢救回来，不至于连证据都没了。
  Future<ScheduleData> load() async {
    final saved = await store.read();

    if (saved != null && saved.trim().isNotEmpty) {
      try {
        return ScheduleData.parse(saved);
      } on Object {
        // 存档坏了。给一份能用的空课表让 App 不至于打不开，但不写盘。
        return ScheduleData.empty();
      }
    }

    // 第一次打开：造一份新的并存下来。
    // 存下来这一步很重要 —— 否则开学日期会随着每次启动「今天」跑，永远定不下来。
    final fresh = _freshData();
    await save(fresh);
    return fresh;
  }

  /// 保存整份课表。
  Future<void> save(ScheduleData data) => store.write(data.toJsonString());

  /// 恢复成刚装好的样子：清掉本机所有改动，回到一份全新的空课表。
  Future<ScheduleData> resetToDefault() async {
    await store.clear();
    final fresh = _freshData();
    await save(fresh);
    return fresh;
  }

  /// 造一份「全新课表」：有 seed 就用 seed，没有就是空课表。
  ScheduleData _freshData() {
    final seed = seedJson;
    if (seed != null && seed.trim().isNotEmpty) {
      try {
        return ScheduleData.parse(seed);
      } on Object {
        // seed 本身有问题也不该让 App 打不开，退回空课表。
      }
    }
    return ScheduleData.empty();
  }
}

/// dandanplay 兼容弹幕条目与解析（纯 Dart，无 IO，便于单测）。
///
/// 服务端返回 `{count, comments: [{id, cid, p, m}]}`，其中 `p` 为
/// 逗号分隔字段：`时间(秒),模式,字号,颜色(十进制)`，`m` 为文本。
/// 模式沿用 bilibili 约定：1/2/3 = 滚动，4 = 底部，5 = 顶部，
/// 6 = 逆向滚动（按滚动处理），7/8 = 精准/代码（按滚动处理）。
enum DanmakuMode {
  /// 滚动（右→左）。
  scroll,

  /// 顶部固定。
  top,

  /// 底部固定。
  bottom,
}

/// 单条弹幕：解析后的轻量模型。
class DanmakuComment {
  /// 出现时间（秒，相对视频起点）。
  final double time;

  /// 展示模式。
  final DanmakuMode mode;

  /// 字体颜色 `0xAARRGGBB`（alpha 统一不透明，整体透明度由调节参数控制）。
  final int color;

  /// 弹幕文本。
  final String text;

  const DanmakuComment({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });

  @override
  String toString() =>
      'DanmakuComment(${time.toStringAsFixed(2)}, $mode, "$text")';
}

/// dandanplay/bilibili 兼容解析器。
class DanmakuParser {
  const DanmakuParser._();

  /// 解析弹幕接口响应（`comments` 数组）；结构异常返回空列表。
  static List<DanmakuComment> parseResponse(Object? json) {
    if (json is! Map) return const [];
    return parseComments(json['comments']);
  }

  /// 解析 `comments` 数组；坏条目（缺 p/m、字段非法）逐条跳过。
  static List<DanmakuComment> parseComments(Object? comments) {
    if (comments is! List) return const [];
    final out = <DanmakuComment>[];
    for (final raw in comments) {
      if (raw is! Map) continue;
      final comment = parseComment(raw);
      if (comment != null) out.add(comment);
    }
    return out;
  }

  /// 解析单条 `{p, m}`；无法解析返回 null。
  static DanmakuComment? parseComment(Map<dynamic, dynamic> raw) {
    final p = raw['p'];
    if (p is! String) return null;
    final m = raw['m'];
    if (m is! String || m.isEmpty) return null;

    final fields = p.split(',');
    if (fields.length < 4) return null;
    final time = double.tryParse(fields[0].trim());
    if (time == null || time < 0) return null;
    final modeRaw = int.tryParse(fields[1].trim());
    if (modeRaw == null) return null;
    final colorRaw = int.tryParse(fields[3].trim());
    if (colorRaw == null) return null;

    return DanmakuComment(
      time: time,
      mode: modeFrom(modeRaw),
      // 十进制色可能只含 RGB；统一补齐不透明 alpha，
      // 整体透明度由用户调节参数在渲染期叠加。
      color: 0xFF000000 | (colorRaw & 0xFFFFFF),
      text: m,
    );
  }

  /// 模式整数 → [DanmakuMode]（未知值按滚动处理）。
  static DanmakuMode modeFrom(int raw) {
    switch (raw) {
      case 4:
        return DanmakuMode.bottom;
      case 5:
        return DanmakuMode.top;
      default:
        return DanmakuMode.scroll;
    }
  }
}

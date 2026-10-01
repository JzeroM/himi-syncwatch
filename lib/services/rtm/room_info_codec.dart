/// roomInfo 消息中媒体条目 ID 的规范化。
///
/// 首页开空房间的路由是 `/player/_`（itemId 为占位符 `_`），
/// 直接当真实 ID 发送会让观众端凭空建出一个名为「电影」的条目。
class RoomInfoCodec {
  const RoomInfoCodec._();

  static const String placeholderItemId = '_';

  /// 占位/空 ID 归一为 null（发送侧不携带该字段）。
  static String? normalizeMediaItemId(String? raw) {
    if (raw == null || raw.isEmpty || raw == placeholderItemId) {
      return null;
    }
    return raw;
  }

  /// 接收侧是否应据 mediaItemId 构建电影条目。
  static bool acceptsMediaItemId(String? raw) =>
      normalizeMediaItemId(raw) != null;
}

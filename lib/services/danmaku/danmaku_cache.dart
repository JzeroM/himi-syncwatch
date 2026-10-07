/// 简单 TTL 内存缓存（泛型，纯 Dart，便于单测）。
///
/// 弹幕用途：`itemId → episodeId` 与 `episodeId → 弹幕列表` 双层缓存，
/// 遵循 dandanplay 开放网络「按 ID 缓存 2~6 小时」的调用约定，
/// 减少重复 match/comment 请求。进程内存级，重启即失效。
class DanmakuCache<T> {
  /// 默认 6 小时（官方建议区间上限，老番数据变动更少）。
  final Duration ttl;

  /// 容量上限（超出按插入序淘汰最旧）。
  final int maxEntries;

  final Map<String, _Entry<T>> _map = {};
  final DateTime Function() _now;

  DanmakuCache({
    this.ttl = const Duration(hours: 6),
    this.maxEntries = 64,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 当前有效条目数（过期项读取时顺带清除，测试可断言）。
  int get length => _map.length;

  /// 取缓存；不存在/已过期返回 null。
  T? get(String key) {
    final entry = _map[key];
    if (entry == null) return null;
    if (_now().difference(entry.at) > ttl) {
      _map.remove(key);
      return null;
    }
    return entry.value;
  }

  /// 写缓存；超容量淘汰最旧插入项。
  void put(String key, T value) {
    _map.remove(key);
    while (_map.length >= maxEntries) {
      _map.remove(_map.keys.first);
    }
    _map[key] = _Entry(value, _now());
  }

  void clear() => _map.clear();
}

class _Entry<T> {
  final T value;
  final DateTime at;
  const _Entry(this.value, this.at);
}

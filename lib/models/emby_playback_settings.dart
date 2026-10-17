/// Emby 播放进度阈值设置（服务器全局或按媒体库）。
///
/// 对应 Emby `ServerConfiguration` / `LibraryOptions` 中的同名字段：
/// - [minResumePct]：低于此百分比不保存/不视为续播（默认 1）。
/// - [maxResumePct]：达到或超过此百分比即视为「已看完」（默认 90）：
///   服务器会清空进度并标记已观看。
/// - [minResumeDurationSeconds]：时长短于此秒数的条目不可续播（默认 3）。
///
/// 解析时同时兼容 PascalCase（Emby REST 返回）与 camelCase（部分代理/兜底）。
class EmbyPlaybackSettings {
  const EmbyPlaybackSettings({
    this.minResumePct = 1,
    this.maxResumePct = 90,
    this.minResumeDurationSeconds = 3,
  });

  final int minResumePct;
  final int maxResumePct;
  final int minResumeDurationSeconds;

  /// Emby 默认值（也是拉取失败时的兜底）。
  static const EmbyPlaybackSettings fallback = EmbyPlaybackSettings();

  factory EmbyPlaybackSettings.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys, int def) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.round();
      }
      return def;
    }

    return EmbyPlaybackSettings(
      minResumePct: readInt(const ['MinResumePct', 'minResumePct'], 1),
      maxResumePct: readInt(const ['MaxResumePct', 'maxResumePct'], 90),
      minResumeDurationSeconds:
          readInt(const ['MinResumeDurationSeconds', 'minResumeDurationSeconds'], 3),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmbyPlaybackSettings &&
      other.minResumePct == minResumePct &&
      other.maxResumePct == maxResumePct &&
      other.minResumeDurationSeconds == minResumeDurationSeconds;

  @override
  int get hashCode =>
      Object.hash(minResumePct, maxResumePct, minResumeDurationSeconds);

  @override
  String toString() =>
      'EmbyPlaybackSettings(min=$minResumePct, max=$maxResumePct, '
      'minDur=${minResumeDurationSeconds}s)';
}

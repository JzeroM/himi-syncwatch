/// 轨表异步就绪前的待下发轨道选择。
///
/// Erika 打开媒体后，原生轨表通过事件异步回传。播放页可能在轨表到达前
/// 就写入 `activeAudioTracks` / `activeSubtitleTracks`；若直接丢弃，引擎会
/// 回落到默认轨。本队列暂存这类请求，待轨表就绪后再下发。
class PendingTrackSelection {
  List<int>? _requested;

  /// 是否有尚未下发的选择。
  bool get hasPending => _requested != null;

  /// 暂存的请求（只读）；无请求时为 null。
  List<int>? get requested =>
      _requested == null ? null : List<int>.unmodifiable(_requested!);

  /// 暂存一次选择；空列表视为「无选择」，不产生待处理请求。
  void request(List<int> tracks) {
    _requested =
        tracks.isEmpty ? null : List<int>.unmodifiable(List<int>.of(tracks));
  }

  /// 媒体切换/销毁时清空，避免旧媒体的选择误用于新轨表。
  void clear() {
    _requested = null;
  }

  /// 取可下发的轨下标；轨表尚未包含该下标时返回 null 并保留请求，
  /// 等待后续轨表扩展（例如追加外挂字幕轨）。
  int? takeReady(int trackCount) {
    final tracks = _requested;
    if (tracks == null || tracks.isEmpty) return null;
    final index = tracks.first;
    if (index < 0 || index >= trackCount) return null;
    _requested = null;
    return index;
  }
}

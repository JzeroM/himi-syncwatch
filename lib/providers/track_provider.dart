import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 详情页预选的音轨/字幕轨（通过 Riverpod 传给播放器，避免 URL 编码问题）。
class TrackSelection {
  /// Emby 音轨 `MediaStream.index`；null = 未预选（播放器用默认音轨）。
  final int? audioIndex;

  /// Emby 字幕轨 `MediaStream.index`；null = 未预选（播放器保持现状默认）、
  /// -1 = 显式关闭字幕、>=0 = 具体字幕轨。
  final int? subtitleIndex;

  const TrackSelection({this.audioIndex, this.subtitleIndex});

  bool get isEmpty => audioIndex == null && subtitleIndex == null;
}

/// 播放入口（开始播放/剧集卡/建房开播）写入，播放器 `_autoSelectDefaultTracks`
/// 消费后置 null。roomMode 下为纯本地偏好，不走 RTM 同步（与播放器内切轨一致）。
final pendingTrackSelectionProvider =
    StateProvider<TrackSelection?>((ref) => null);

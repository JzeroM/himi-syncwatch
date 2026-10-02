import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';

/// 详情页预选应用到播放器后的初始轨道参数（纯 Dart，可单测）。
///
/// 所有 `position` 均为 `MediaStream` 在对应列表中的**位置**
/// （与 fvp `activeAudioTracks`/`activeSubtitleTracks` 的内部索引一致，
/// 与 `_selectEmbySubtitle`/`_selectEmbyAudio` 的入参语义一致），
/// 不是 Emby 的 `MediaStream.index`。
class ResolvedInitialTracks {
  /// true = 需要应用字幕预选；false = 无字幕预选或未匹配到轨（走播放器默认）。
  final bool applySubtitle;

  /// [applySubtitle] 时有效：null = 关闭字幕（-1），int = 列表位置。
  final int? subtitlePosition;

  /// true = 音轨预选匹配成功；false = 走播放器默认音轨逻辑。
  final bool applyAudio;

  final int? audioPosition;

  const ResolvedInitialTracks({
    required this.applySubtitle,
    this.subtitlePosition,
    required this.applyAudio,
    this.audioPosition,
  });

  /// 字幕预选为「关闭」。
  bool get subtitleOff => applySubtitle && subtitlePosition == null;
}

/// 把详情页的 [TrackSelection]（Emby `MediaStream.index` 语义）解析为
/// 播放器可直接应用的列表位置。
///
/// 返回 null = 无需应用（无预选），播放器完全走原有默认逻辑。
/// 预选的 index 在流列表中匹配不到时，该轨回退默认（不强行应用）。
ResolvedInitialTracks? resolveInitialTracks({
  required TrackSelection? pending,
  required List<MediaStream> audioStreams,
  required List<MediaStream> subtitleStreams,
}) {
  if (pending == null || pending.isEmpty) return null;

  var applyAudio = false;
  int? audioPosition;
  final audioIndex = pending.audioIndex;
  if (audioIndex != null) {
    final i = audioStreams.indexWhere((s) => s.index == audioIndex);
    if (i >= 0) {
      applyAudio = true;
      audioPosition = i;
    }
  }

  var applySubtitle = false;
  int? subtitlePosition;
  final subtitleIndex = pending.subtitleIndex;
  if (subtitleIndex != null) {
    if (subtitleIndex < 0) {
      // -1 = 显式关闭字幕
      applySubtitle = true;
      subtitlePosition = null;
    } else {
      final i = subtitleStreams.indexWhere((s) => s.index == subtitleIndex);
      if (i >= 0) {
        applySubtitle = true;
        subtitlePosition = i;
      }
    }
  }

  if (!applyAudio && !applySubtitle) return null;

  return ResolvedInitialTracks(
    applySubtitle: applySubtitle,
    subtitlePosition: subtitlePosition,
    applyAudio: applyAudio,
    audioPosition: audioPosition,
  );
}

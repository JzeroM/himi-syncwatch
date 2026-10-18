import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';

/// 版本切换时的预选轨迁移（纯函数）：不同版本的 `MediaStream.index`
/// 归属不同流集，直接沿用会错轨，故按「语言 + 类型」在新版本里找同
/// 语言轨；找不到则该轨清空。
///
/// [keepNegative]：字幕的 -1（显式关闭）需原样保留；音轨不保留。
/// 返回 null 表示两轨都被清空，调用方可据此整体清掉预选。
TrackSelection? migrateTrackSelection(
  TrackSelection selection, {
  required List<MediaStream> oldAudio,
  required List<MediaStream> newAudio,
  required List<MediaStream> oldSubtitle,
  required List<MediaStream> newSubtitle,
}) {
  int? migrate(
    int? index,
    List<MediaStream> from,
    List<MediaStream> to, {
    bool keepNegative = false,
  }) {
    if (index == null) return null;
    if (index < 0) return keepNegative ? index : null;
    MediaStream? old;
    for (final s in from) {
      if (s.index == index) {
        old = s;
        break;
      }
    }
    if (old == null) return null;
    final lang = old.language ?? old.displayLanguage;
    if (lang == null || lang.isEmpty) return null;
    for (final s in to) {
      final l = s.language ?? s.displayLanguage;
      if (l == lang) return s.index;
    }
    return null;
  }

  final newAudioIndex = migrate(selection.audioIndex, oldAudio, newAudio);
  final newSubtitleIndex = migrate(
    selection.subtitleIndex,
    oldSubtitle,
    newSubtitle,
    keepNegative: true,
  );
  if (newAudioIndex == null && newSubtitleIndex == null) return null;
  return TrackSelection(
    audioIndex: newAudioIndex,
    subtitleIndex: newSubtitleIndex,
  );
}

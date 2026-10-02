import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/screens/player/track_initial_selection.dart';

void main() {
  final audioStreams = [
    MediaStream(type: 'Audio', codec: 'aac', index: 0),
    MediaStream(type: 'Audio', codec: 'ac3', index: 2),
  ];
  final subtitleStreams = [
    MediaStream(type: 'Subtitle', codec: 'srt', index: 3),
    MediaStream(type: 'Subtitle', codec: 'ass', index: 5),
  ];

  group('resolveInitialTracks', () {
    test('无预选（null / isEmpty）返回 null，播放器走默认逻辑', () {
      expect(
        resolveInitialTracks(
          pending: null,
          audioStreams: audioStreams,
          subtitleStreams: subtitleStreams,
        ),
        isNull,
      );
      expect(
        resolveInitialTracks(
          pending: const TrackSelection(),
          audioStreams: audioStreams,
          subtitleStreams: subtitleStreams,
        ),
        isNull,
      );
    });

    test('音轨 index 匹配 → 转为列表位置（Emby index≠位置）', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(audioIndex: 2),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      expect(resolved, isNotNull);
      expect(resolved!.applyAudio, isTrue);
      expect(resolved.audioPosition, 1, reason: 'Emby index 2 在列表第 2 位');
      expect(resolved.applySubtitle, isFalse);
    });

    test('音轨 index 匹配不到 → 该轨回退默认（整体 null）', () {
      expect(
        resolveInitialTracks(
          pending: const TrackSelection(audioIndex: 99),
          audioStreams: audioStreams,
          subtitleStreams: subtitleStreams,
        ),
        isNull,
      );
    });

    test('字幕 -1 → 关闭字幕（subtitleOff）', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(subtitleIndex: -1),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      expect(resolved, isNotNull);
      expect(resolved!.applySubtitle, isTrue);
      expect(resolved.subtitleOff, isTrue);
      expect(resolved.subtitlePosition, isNull);
      expect(resolved.applyAudio, isFalse);
    });

    test('字幕 index 匹配 → 列表位置', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(subtitleIndex: 5),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      expect(resolved!.applySubtitle, isTrue);
      expect(resolved.subtitlePosition, 1);
      expect(resolved.subtitleOff, isFalse);
    });

    test('字幕 index 匹配不到 → 回退默认（applySubtitle=false）', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(subtitleIndex: 42),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      // 字幕未匹配、无音轨预选 → 整体无预选
      expect(resolved, isNull);
    });

    test('音轨+字幕同时预选：各自独立解析', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(audioIndex: 0, subtitleIndex: 3),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      expect(resolved!.applyAudio, isTrue);
      expect(resolved.audioPosition, 0);
      expect(resolved.applySubtitle, isTrue);
      expect(resolved.subtitlePosition, 0);
    });

    test('音轨预选匹配失败但字幕成功：音轨回退默认、字幕仍应用', () {
      final resolved = resolveInitialTracks(
        pending: const TrackSelection(audioIndex: 99, subtitleIndex: -1),
        audioStreams: audioStreams,
        subtitleStreams: subtitleStreams,
      );

      expect(resolved, isNotNull);
      expect(resolved!.applyAudio, isFalse, reason: '音轨未匹配回退默认');
      expect(resolved.applySubtitle, isTrue);
      expect(resolved.subtitleOff, isTrue);
    });
  });
}

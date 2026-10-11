import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/media_kit_player_adapter.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('MediaKitPlayerAdapter.filterRealTracks', () {
    test('过滤 auto/no 哨兵，保留真实轨', () {
      final tracks = [
        AudioTrack.auto(),
        AudioTrack.no(),
        AudioTrack('1', 'AAC 5.1', 'eng'),
        AudioTrack('2', 'DTS-HD', 'chi'),
        AudioTrack('3', 'TrueHD', 'jpn'),
      ];
      final real = MediaKitPlayerAdapter.filterRealTracks(
          tracks, (t) => t.id);
      expect(real.length, 3);
      expect(real[0].id, '1');
      expect(real[1].id, '2');
      expect(real[2].id, '3');
      expect(real[0].title, 'AAC 5.1');
      expect(real[1].language, 'chi');
    });

    test('空列表返回空', () {
      final real =
          MediaKitPlayerAdapter.filterRealTracks(<AudioTrack>[], (t) => t.id);
      expect(real, isEmpty);
    });

    test('仅哨兵时返回空', () {
      final tracks = [SubtitleTrack.auto(), SubtitleTrack.no()];
      final real = MediaKitPlayerAdapter.filterRealTracks(
          tracks, (t) => t.id);
      expect(real, isEmpty);
    });

    test('字幕轨过滤', () {
      final tracks = [
        SubtitleTrack.auto(),
        SubtitleTrack.no(),
        SubtitleTrack('1', 'SRT', 'eng'),
        SubtitleTrack('2', 'PGS', 'chi'),
      ];
      final real = MediaKitPlayerAdapter.filterRealTracks(
          tracks, (t) => t.id);
      expect(real.length, 2);
      expect(real[0].id, '1');
      expect(real[1].id, '2');
    });

    test('视轨过滤', () {
      final tracks = [
        VideoTrack.auto(),
        VideoTrack.no(),
        const VideoTrack('1', 'HEVC 4K', 'eng', codec: 'hevc'),
      ];
      final real = MediaKitPlayerAdapter.filterRealTracks(
          tracks, (t) => t.id);
      expect(real.length, 1);
      expect(real[0].id, '1');
      expect(real[0].codec, 'hevc');
    });

    test('Emby 位置 → 真实轨位置 映射（核心回归）', () {
      // 模拟 media_kit 状态：[auto, no, 真轨1, 真轨2, 真轨3]
      final tracks = [
        AudioTrack.auto(),
        AudioTrack.no(),
        AudioTrack('1', 'English', 'eng'),
        AudioTrack('2', 'Chinese', 'chi'),
        AudioTrack('3', 'Japanese', 'jpn'),
      ];
      final real = MediaKitPlayerAdapter.filterRealTracks(
          tracks, (t) => t.id);

      // Emby 位置 0 → 真轨1（English）
      expect(real[0].language, 'eng');
      // Emby 位置 1 → 真轨2（Chinese）——修复前命中 no 导致静音
      expect(real[1].language, 'chi');
      // Emby 位置 2 → 真轨3（Japanese）——修复前命中真轨1
      expect(real[2].language, 'jpn');
    });
  });
}

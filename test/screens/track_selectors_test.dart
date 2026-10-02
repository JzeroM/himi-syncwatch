import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/screens/detail/track_selectors.dart';

MediaStream audio(int idx, String lang) =>
    MediaStream(type: 'Audio', codec: 'aac', language: lang, index: idx);

MediaStream sub(int idx, String lang) =>
    MediaStream(type: 'Subtitle', codec: 'srt', language: lang, index: idx);

void main() {
  group('migrateTrackSelection（版本切换预选迁移）', () {
    final oldAudio = [audio(0, 'chi'), audio(1, 'eng')];
    final newAudio = [audio(0, 'eng'), audio(1, 'chi')]; // index 集不同
    final oldSub = [sub(3, 'chi'), sub(4, 'eng')];
    final newSub = [sub(8, 'eng'), sub(9, 'chi')];

    test('按语言迁移：chi 音轨与字幕在新版本找到同语言轨', () {
      const sel = TrackSelection(audioIndex: 0, subtitleIndex: 3);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: newAudio,
        oldSubtitle: oldSub,
        newSubtitle: newSub,
      );
      expect(migrated?.audioIndex, 1, reason: 'old chi(0) → new chi(1)');
      expect(migrated?.subtitleIndex, 9, reason: 'old chi(3) → new chi(9)');
    });

    test('新版本无同语言轨 → 该轨清空；两轨都清返回 null', () {
      const sel = TrackSelection(audioIndex: 0, subtitleIndex: 3); // 均为 chi
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: [
          MediaStream(type: 'Audio', codec: 'ac3', language: 'jpn', index: 0)
        ],
        oldSubtitle: oldSub,
        newSubtitle: [
          MediaStream(type: 'Subtitle', codec: 'ass', language: 'eng', index: 8)
        ],
      );
      expect(migrated, isNull, reason: '两轨都清空时整体清预选');
    });

    test('仅音轨无匹配 → 音轨清空、字幕保留', () {
      const sel = TrackSelection(audioIndex: 0, subtitleIndex: 3); // 均为 chi
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: [
          MediaStream(type: 'Audio', codec: 'ac3', language: 'jpn', index: 0)
        ],
        oldSubtitle: oldSub,
        newSubtitle: newSub, // 有 chi(9)
      );
      expect(migrated?.audioIndex, isNull);
      expect(migrated?.subtitleIndex, 9);
    });

    test('字幕 -1（显式关闭）原样保留', () {
      const sel = TrackSelection(audioIndex: 0, subtitleIndex: -1);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: newAudio,
        oldSubtitle: oldSub,
        newSubtitle: newSub,
      );
      expect(migrated?.audioIndex, 1);
      expect(migrated?.subtitleIndex, -1, reason: '关闭字幕不因换版本丢掉');
    });

    test('音轨负值不保留（音轨无关闭语义）', () {
      const sel = TrackSelection(audioIndex: -1, subtitleIndex: null);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: newAudio,
        oldSubtitle: oldSub,
        newSubtitle: newSub,
      );
      expect(migrated, isNull);
    });

    test('旧轨 index 不在旧流集 → 视为无从匹配，清空', () {
      const sel = TrackSelection(audioIndex: 99, subtitleIndex: null);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: newAudio,
        oldSubtitle: oldSub,
        newSubtitle: newSub,
      );
      expect(migrated, isNull);
    });

    test('未预选的轨（null）保持 null，不影响另一轨迁移', () {
      const sel = TrackSelection(audioIndex: null, subtitleIndex: 3);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: oldAudio,
        newAudio: newAudio,
        oldSubtitle: oldSub,
        newSubtitle: newSub,
      );
      expect(migrated?.audioIndex, isNull);
      expect(migrated?.subtitleIndex, 9);
    });

    test('displayLanguage 回退：language 为空时用 displayLanguage 匹配', () {
      final withDisplay = [
        MediaStream(
            type: 'Audio', codec: 'aac', displayLanguage: '中文', index: 5),
      ];
      final toDisplay = [
        MediaStream(
            type: 'Audio', codec: 'ac3', displayLanguage: '中文', index: 2),
      ];
      const sel = TrackSelection(audioIndex: 5, subtitleIndex: null);
      final migrated = migrateTrackSelection(
        sel,
        oldAudio: withDisplay,
        newAudio: toDisplay,
        oldSubtitle: const [],
        newSubtitle: const [],
      );
      expect(migrated?.audioIndex, 2);
    });
  });
}

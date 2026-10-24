import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_playback_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/playback_rules.dart';

MediaItem _item({
  int ms = 0,
  double pct = 0,
  bool watched = false,
  int? ticks = 3000000000, // 300s
}) =>
    MediaItem(
      id: 'x',
      name: 'x',
      type: 'Episode',
      playbackPositionMs: ms,
      playedPercentage: pct,
      isWatched: watched,
      runTimeTicks: ticks,
    );

void main() {
  const s = EmbyPlaybackSettings.fallback; // min 1 / max 90 / minDur 3s

  group('EmbyPlaybackSettings', () {
    test('从 Emby PascalCase 解析', () {
      final r = EmbyPlaybackSettings.fromJson(const {
        'MinResumePct': 5,
        'MaxResumePct': 95,
        'MinResumeDurationSeconds': 10,
      });
      expect(r.minResumePct, 5);
      expect(r.maxResumePct, 95);
      expect(r.minResumeDurationSeconds, 10);
    });

    test('缺字段回退默认', () {
      final r = EmbyPlaybackSettings.fromJson(const {});
      expect(r, EmbyPlaybackSettings.fallback);
    });
  });

  group('PlaybackRules.isFinished', () {
    test('已观看标记 → true', () {
      expect(PlaybackRules.isFinished(_item(pct: 0, watched: true), s), isTrue);
    });
    test('pct 达到上限 → true', () {
      expect(PlaybackRules.isFinished(_item(pct: 90), s), isTrue);
    });
    test('pct 低于上限 → false', () {
      expect(PlaybackRules.isFinished(_item(pct: 89), s), isFalse);
    });
    test('百分比缺失但位置已达上限 → true', () {
      expect(PlaybackRules.isFinished(_item(ms: 270000, pct: 0), s), isTrue);
    });
  });

  group('PlaybackRules.resumePercentage', () {
    test('PlayedPercentage 缺失时按位置/时长补算', () {
      expect(
        PlaybackRules.resumePercentage(_item(ms: 60000, pct: 0)),
        closeTo(20, 0.001),
      );
    });

    test('已有 PlayedPercentage 时保留服务器值', () {
      expect(PlaybackRules.resumePercentage(_item(ms: 60000, pct: 12.5)), 12.5);
    });

    test('无时长或无进度返回原值', () {
      expect(PlaybackRules.resumePercentage(_item(ms: 60000, ticks: null)), 0);
      expect(PlaybackRules.resumePercentage(_item(ms: 0, pct: 0)), 0);
    });
  });

  group('PlaybackRules.isResumable', () {
    test('百分比缺失但位置可补算 → true', () {
      expect(PlaybackRules.isResumable(_item(ms: 60000, pct: 0), s), isTrue);
    });

    test('正常进度 → true', () {
      expect(PlaybackRules.isResumable(_item(ms: 1000, pct: 10), s), isTrue);
    });
    test('无播放进度 → false', () {
      expect(PlaybackRules.isResumable(_item(ms: 0, pct: 10), s), isFalse);
    });
    test('已标记已观看 → false', () {
      expect(
        PlaybackRules.isResumable(_item(ms: 1000, pct: 10, watched: true), s),
        isFalse,
      );
    });
    test('pct 低于下限（MinResumePct）→ false', () {
      expect(PlaybackRules.isResumable(_item(ms: 10, pct: 0.5), s), isFalse);
    });
    test('pct 达上限 → false', () {
      expect(PlaybackRules.isResumable(_item(ms: 10, pct: 90), s), isFalse);
    });
    test('时长低于下限（MinResumeDurationSeconds）→ false', () {
      expect(
        PlaybackRules.isResumable(_item(ms: 10, pct: 10, ticks: 20000000), s),
        isFalse,
      );
    });
    test('时长未知不据此拦截', () {
      expect(
        PlaybackRules.isResumable(_item(ms: 10, pct: 10, ticks: null), s),
        isTrue,
      );
    });
  });

  test('durationSeconds：ticks ÷ 1e7', () {
    expect(PlaybackRules.durationSeconds(_item(ticks: 3000000000)), 300);
    expect(PlaybackRules.durationSeconds(_item(ticks: null)), 0);
  });
}

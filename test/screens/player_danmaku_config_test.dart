import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_timeline.dart';

void main() {
  group('PlayerScreen.danmakuTimelineConfig（设置 → 时间轴映射）', () {
    test('默认设置映射：行数 4 / 无屏蔽 / 不限数量', () {
      final c = PlayerScreen.danmakuTimelineConfig(const AppSettings());
      expect(c.scrollRows, 4);
      expect(c.topRows, 4);
      expect(c.bottomRows, 4);
      expect(c.blockTop, isFalse);
      expect(c.blockBottom, isFalse);
      expect(c.blockWords, isEmpty);
      expect(c.maxCount, isNull);
    });

    test('屏蔽词按英文逗号拆分并去空白/空段', () {
      final c = PlayerScreen.danmakuTimelineConfig(
        const AppSettings(danmakuBlockWords: '广告 , 刷屏,, '),
      );
      expect(c.blockWords, ['广告', '刷屏']);
    });

    test('限制数量开关：关 → null，开 → 上限值', () {
      expect(
        PlayerScreen.danmakuTimelineConfig(const AppSettings()).maxCount,
        isNull,
      );
      expect(
        PlayerScreen.danmakuTimelineConfig(
          const AppSettings(danmakuLimitCount: true, danmakuMaxCount: 300),
        ).maxCount,
        300,
      );
    });

    test('行数/顶底屏蔽透传', () {
      final c = PlayerScreen.danmakuTimelineConfig(
        const AppSettings(
          danmakuScrollRows: 8,
          danmakuTopRows: 2,
          danmakuBottomRows: 6,
          danmakuBlockTop: true,
          danmakuBlockBottom: true,
        ),
      );
      expect(c.scrollRows, 8);
      expect(c.topRows, 2);
      expect(c.bottomRows, 6);
      expect(c.blockTop, isTrue);
      expect(c.blockBottom, isTrue);
    });

    test('与过滤链联动：配置直接可用于时间轴构造', () {
      final config = PlayerScreen.danmakuTimelineConfig(
        const AppSettings(danmakuBlockWords: '广告'),
      );
      final timeline = DanmakuTimeline(
        comments: [
          DanmakuComment(
            time: 0,
            mode: DanmakuMode.scroll,
            color: 0xFFFFFFFF,
            text: '广告内容',
          ),
        ],
        config: config,
        screenWidth: 1280,
      );
      expect(timeline.totalCount, 0, reason: '屏蔽词生效');
    });
  });
}

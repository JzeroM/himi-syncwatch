import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_timeline.dart';

DanmakuComment _c(
  double time, {
  String text = '测试',
  DanmakuMode mode = DanmakuMode.scroll,
}) =>
    DanmakuComment(time: time, mode: mode, color: 0xFFFFFFFF, text: text);

void main() {
  group('DanmakuTimeline.activeAt', () {
    test('基本生命周期：出现前/存活中/消失后', () {
      final tl = DanmakuTimeline(
        comments: [_c(1.0)],
        config: const DanmakuTimelineConfig(),
        screenWidth: 1280,
      );
      expect(tl.activeAt(const Duration(milliseconds: 999)), isEmpty);
      final mid = tl.activeAt(const Duration(milliseconds: 4000));
      expect(mid.single.progress, closeTo(3.0 / 8.0, 1e-9));
      // 存活 8s：1.0s 出现，9.0s 消失（含首不含尾）
      expect(tl.activeAt(const Duration(milliseconds: 8999)).length, 1);
      expect(tl.activeAt(const Duration(milliseconds: 9000)), isEmpty);
    });

    test('speed=2 穿屏时长减半（基准 8s ÷ speed）', () {
      final tl = DanmakuTimeline(
        comments: [_c(0)],
        config: const DanmakuTimelineConfig(),
        screenWidth: 1280,
        speed: 2.0,
      );
      expect(tl.scrollDurationSeconds, 4.0);
      expect(tl.activeAt(const Duration(milliseconds: 3999)).length, 1);
      expect(tl.activeAt(const Duration(milliseconds: 4000)), isEmpty);
    });

    test('顶部/底部固定 4s，不受 speed 影响', () {
      final tl = DanmakuTimeline(
        comments: [
          _c(0, mode: DanmakuMode.top),
          _c(0, mode: DanmakuMode.bottom)
        ],
        config: const DanmakuTimelineConfig(),
        screenWidth: 1280,
        speed: 0.5,
      );
      expect(tl.activeAt(const Duration(seconds: 2)).length, 2);
      expect(tl.activeAt(const Duration(seconds: 4)), isEmpty);
    });

    test('seek 确定性：同位置两次查询一致，回退与前进结果由位置唯一决定', () {
      final tl = DanmakuTimeline(
        comments: [_c(1), _c(2), _c(10)],
        config: const DanmakuTimelineConfig(),
        screenWidth: 1280,
      );
      final a = tl.activeAt(const Duration(seconds: 3));
      final b = tl.activeAt(const Duration(seconds: 3));
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].row, b[i].row);
        expect(a[i].progress, b[i].progress);
      }
      // 回退到 1.5s：只显示第一条（快进/回退无需重建）
      final back = tl.activeAt(const Duration(milliseconds: 1500));
      expect(back.single.comment.time, 1.0);
    });

    test('多条同时活跃均返回', () {
      final tl = DanmakuTimeline(
        comments: [_c(0), _c(1), _c(2)],
        config: const DanmakuTimelineConfig(),
        screenWidth: 1280,
      );
      expect(tl.activeAt(const Duration(seconds: 3)).length, 3);
    });
  });

  group('DanmakuTimeline 轨道分配', () {
    test('同行数=1 时：轨道占用内新弹幕被丢弃，释放后可复用', () {
      // 中文 2 字：宽度 50，占用 ≈ 8×50/1330 + 0.15 ≈ 0.451s
      final tl = DanmakuTimeline(
        comments: [_c(0.0), _c(0.2, text: '测试'), _c(0.5, text: '测试')],
        config: const DanmakuTimelineConfig(scrollRows: 1),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 2, reason: '0.2s 被占用丢弃，0.5s 复用成功');
      expect(tl.filtered.first.time, 0.0);
      expect(tl.filtered.last.time, 0.5);
    });

    test('多行滚动：同时刻弹幕分配到不同轨道', () {
      final tl = DanmakuTimeline(
        comments: [_c(0), _c(0), _c(0)],
        config: const DanmakuTimelineConfig(scrollRows: 3),
        screenWidth: 1280,
      );
      final act = tl.activeAt(Duration.zero);
      expect(act.length, 3);
      expect({for (final a in act) a.row}, {0, 1, 2});
    });

    test('顶部与底部轨道各自独立计数', () {
      final tl = DanmakuTimeline(
        comments: [
          _c(0, mode: DanmakuMode.top),
          _c(0, mode: DanmakuMode.top),
          _c(0, mode: DanmakuMode.bottom),
        ],
        config: const DanmakuTimelineConfig(topRows: 2, bottomRows: 1),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 3);
      final act = tl.activeAt(Duration.zero);
      expect(
        act.where((a) => a.comment.mode == DanmakuMode.top).map((a) => a.row),
        {0, 1},
      );
      expect(
        act.where((a) => a.comment.mode == DanmakuMode.bottom).single.row,
        0,
      );
    });

    test('超出行数的密集弹幕被丢弃', () {
      final tl = DanmakuTimeline(
        comments: [_c(0), _c(0), _c(0), _c(0)],
        config: const DanmakuTimelineConfig(scrollRows: 2),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 2);
    });

    test('顶部行满后底部不受影响（独立池）', () {
      final tl = DanmakuTimeline(
        comments: [
          _c(0, mode: DanmakuMode.top),
          _c(0, mode: DanmakuMode.top), // topRows=1 → 丢弃
          _c(0, mode: DanmakuMode.bottom),
        ],
        config: const DanmakuTimelineConfig(topRows: 1, bottomRows: 1),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 2);
    });
  });

  group('DanmakuTimeline 过滤链', () {
    test('blockTop/blockBottom', () {
      final tl = DanmakuTimeline(
        comments: [
          _c(0),
          _c(0, mode: DanmakuMode.top),
          _c(0, mode: DanmakuMode.bottom),
        ],
        config: const DanmakuTimelineConfig(blockTop: true, blockBottom: true),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 1);
      expect(tl.filtered.single.mode, DanmakuMode.scroll);
    });

    test('屏蔽词子串匹配，空词忽略', () {
      final tl = DanmakuTimeline(
        comments: [
          _c(0, text: '广告内容'),
          _c(0, text: '正常弹幕'),
          _c(1, text: '广告'),
        ],
        config: const DanmakuTimelineConfig(blockWords: ['广告', '']),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 1);
      expect(tl.filtered.single.text, '正常弹幕');
    });

    test('maxCount 等间隔采样保留首条', () {
      final comments = [for (var i = 0; i < 20; i++) _c(i.toDouble())];
      final tl = DanmakuTimeline(
        comments: comments,
        config: const DanmakuTimelineConfig(maxCount: 5),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 5);
      expect(tl.filtered.first.time, 0.0, reason: '保留首条');
      final times = tl.filtered.map((c) => c.time).toList();
      expect(times.toSet().length, 5, reason: '不重复采样');
    });

    test('未超限时 maxCount 不生效', () {
      final tl = DanmakuTimeline(
        comments: [_c(0), _c(1)],
        config: const DanmakuTimelineConfig(maxCount: 5),
        screenWidth: 1280,
      );
      expect(tl.totalCount, 2);
    });

    test('filtered 按时间升序', () {
      final tl = DanmakuTimeline(
        comments: [_c(5), _c(1), _c(3)],
        config: const DanmakuTimelineConfig(scrollRows: 10),
        screenWidth: 1280,
      );
      expect(tl.filtered.map((c) => c.time), [1, 3, 5]);
    });
  });

  group('DanmakuTimeline.estimateTextWidth', () {
    test('CJK 全角 1.0×字号，ASCII 0.55×字号', () {
      expect(DanmakuTimeline.estimateTextWidth('测', 25), 25);
      expect(DanmakuTimeline.estimateTextWidth('a', 25), closeTo(13.75, 1e-9));
      expect(
        DanmakuTimeline.estimateTextWidth('ab中文', 20),
        closeTo(2 * 20 * 0.55 + 2 * 20, 1e-9),
      );
    });

    test('空串宽度 0', () {
      expect(DanmakuTimeline.estimateTextWidth('', 25), 0);
    });
  });
}

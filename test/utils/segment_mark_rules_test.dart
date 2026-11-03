import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/segment_mark_rules.dart';

/// 手动片头/片尾标记范围约束（588）。
///
/// 规则：片头结束点 ≤ 总时长 10%；片尾开始点 ≥ 总时长 70%。
/// 时长未知（<=0）不校验。三端（Dart/安卓/鸿蒙）阈值与文案必须逐字一致。
void main() {
  group('片头：不能超过总时长 10%', () {
    const durationMs = 3600000; // 60 分钟 → 上限 6 分钟

    test('上限值', () {
      expect(SegmentMarkRules.introMaxMs(durationMs), 360000);
      expect(SegmentMarkRules.introMaxFraction, 0.10);
    });

    test('边界：恰好 10% 通过，超出 1ms 拒绝', () {
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: true,
          positionMs: 360000,
          durationMs: durationMs,
        ),
        isNull,
      );
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: true,
          positionMs: 360001,
          durationMs: durationMs,
        ),
        SegmentMarkRules.introRejectMessage,
      );
    });

    test('9.9% 通过 / 10.1% 拒绝', () {
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: true,
          positionMs: 356400,
          durationMs: durationMs,
        ),
        isNull,
      );
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: true,
          positionMs: 363600,
          durationMs: durationMs,
        ),
        SegmentMarkRules.introRejectMessage,
      );
    });

    test('整数运算向下取整（避免浮点边界差 1ms）', () {
      // 999ms × 10% = 99.9ms → 99ms
      expect(SegmentMarkRules.introMaxMs(999), 99);
      expect(SegmentMarkRules.introMaxMs(1001), 100);
    });
  });

  group('片尾：不能低于总时长 70%', () {
    const durationMs = 3600000; // 60 分钟 → 下限 42 分钟

    test('下限值', () {
      expect(SegmentMarkRules.outroMinMs(durationMs), 2520000);
      expect(SegmentMarkRules.outroMinFraction, 0.70);
    });

    test('边界：恰好 70% 通过，低 1ms 拒绝', () {
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: false,
          positionMs: 2520000,
          durationMs: durationMs,
        ),
        isNull,
      );
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: false,
          positionMs: 2519999,
          durationMs: durationMs,
        ),
        SegmentMarkRules.outroRejectMessage,
      );
    });

    test('69.9% 拒绝 / 70.1% 通过', () {
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: false,
          positionMs: 2516400,
          durationMs: durationMs,
        ),
        SegmentMarkRules.outroRejectMessage,
      );
      expect(
        SegmentMarkRules.rejectReason(
          isIntro: false,
          positionMs: 2523600,
          durationMs: durationMs,
        ),
        isNull,
      );
    });

    test('整数运算向上取整', () {
      // 999ms × 70% = 699.3ms → 700ms（向上取整，保证「不低于 70%」）
      expect(SegmentMarkRules.outroMinMs(999), 700);
      expect(SegmentMarkRules.outroMinMs(1000), 700);
    });
  });

  group('时长未知（直播/转码流）不校验范围', () {
    test('durationMs = 0 一律通过', () {
      for (final isIntro in <bool>[true, false]) {
        expect(
          SegmentMarkRules.rejectReason(
            isIntro: isIntro,
            positionMs: 123456789,
            durationMs: 0,
          ),
          isNull,
        );
      }
      expect(SegmentMarkRules.introMaxMs(0), isNull);
      expect(SegmentMarkRules.outroMinMs(0), isNull);
    });
  });

  test('拒绝文案与三端原生逐字一致', () {
    const intro = '片头结束点不能超过总时长的 10%';
    const outro = '片尾开始点不能低于总时长的 70%';
    expect(SegmentMarkRules.introRejectMessage, intro);
    expect(SegmentMarkRules.outroRejectMessage, outro);
  });
}

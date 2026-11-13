import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';

/// 697：播放调试面板的数据模型（`DebugMetrics` / `VideoColorInfo`）。
///
/// ## 为什么单独测模型
///
/// 面板的价值在于**准确显示 HDR/DV 参数**。模型解析错一个字段，
/// 排查时就会得出错误结论（比如把 P5 当 P8，误以为「libplacebo 能处理」）。
///
/// ## HDR/DV 排查的关键三元组
///
/// | 层 | 数据源 | 回答 |
/// |---|---|---|
/// | 输入 | `video-params` | 片源是什么？ |
/// | 决策 | `dvContent`/`hdrContent` | 识别成什么了？ |
/// | 输出 | `target-trc`/`tone-mapping` | 怎么渲染的？ |
void main() {
  group('1. VideoColorInfo 解析 video-params', () {
    test('1.1 HDR10 完整字段', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'pixelformat': 'yuv420p10',
        'w': 3840,
        'h': 2160,
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'sig-peak': 1000.0,
        'min-luma': 0.0001,
        'max-luma': 1000.0,
      }));

      expect(v, isNotNull);
      expect(v!.width, 3840);
      expect(v.height, 2160);
      expect(v.primaries, 'bt.2020');
      expect(v.gamma, 'pq');
      expect(v.sigPeak, 1000.0);
      expect(v.isHdr, isTrue);
      expect(v.isHlg, isFalse);
      expect(v.isDolbyVision, isFalse);
      expect(v.bitDepth, 10);
    });

    test('1.2 杜比视界 P8', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'pixelformat': 'yuv420p10',
        'w': 3840,
        'h': 2160,
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'dovi-profile': 8,
        'dovi-level': 6,
      }));

      expect(v!.isDolbyVision, isTrue);
      expect(v.doviProfile, 8);
      expect(v.doviLevel, 6);
      expect(v.doviLabel, 'P8');
    });

    test('1.3 杜比视界 P5', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'pixelformat': 'yuv420p10',
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'dovi-profile': 5,
      }));

      expect(v!.isDolbyVision, isTrue);
      expect(v.doviProfile, 5);
      expect(v.doviLabel, 'P5');
    });

    test('1.4 HLG 内容', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'pixelformat': 'yuv420p10',
        'primaries': 'bt.2020',
        'gamma': 'hlg',
      }));

      expect(v!.isHdr, isTrue);
      expect(v.isHlg, isTrue);
    });

    test('1.5 SDR 内容', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'pixelformat': 'yuv420p',
        'primaries': 'bt.709',
        'gamma': 'bt.1886',
      }));

      expect(v!.isHdr, isFalse);
      expect(v.isDolbyVision, isFalse);
      expect(v.bitDepth, 8);
    });

    test('1.6 位深从 pixelformat 推断', () {
      int depth(String fmt) =>
          VideoColorInfo.tryParse(jsonEncode({'pixelformat': fmt}))!.bitDepth;
      expect(depth('yuv420p'), 8);
      expect(depth('yuv420p10'), 10);
      expect(depth('yuv420p12'), 12);
      // 非标准格式兜底
      expect(depth('p010'), 10);
    });

    test('1.7 空/非法输入返回 null', () {
      expect(VideoColorInfo.tryParse(null), isNull);
      expect(VideoColorInfo.tryParse(''), isNull);
      expect(VideoColorInfo.tryParse('not json'), isNull);
      expect(VideoColorInfo.tryParse('[1,2,3]'), isNull);
    });

    test('1.8 缺字段时用默认值（不抛）', () {
      final v = VideoColorInfo.tryParse(jsonEncode({'w': 1920}));
      expect(v, isNotNull);
      expect(v!.width, 1920);
      expect(v.primaries, '');
      expect(v.sigPeak, 0);
      expect(v.isHdr, isFalse);
    });
  });

  group('2. DebugMetrics 文本导出', () {
    test('2.1 按分组输出「标签: 值」', () {
      const m = DebugMetrics([
        DebugMetricGroup(
          title: '播放',
          rows: [
            DebugMetricRow('状态', 'playing'),
            DebugMetricRow('位置', '00:12 / 00:45'),
          ],
        ),
        DebugMetricGroup(
          title: 'HDR 输入',
          rows: [DebugMetricRow('色彩', 'bt.2020 / pq')],
        ),
      ]);

      final text = m.toPlainText();
      expect(text, contains('## 播放'));
      expect(text, contains('状态: playing'));
      expect(text, contains('位置: 00:12 / 00:45'));
      expect(text, contains('## HDR 输入'));
      expect(text, contains('色彩: bt.2020 / pq'));
    });

    test('2.2 空分组不输出标题', () {
      const m = DebugMetrics([
        DebugMetricGroup(title: '播放', rows: []),
        DebugMetricGroup(title: 'HDR', rows: [DebugMetricRow('色彩', 'pq')]),
      ]);
      final text = m.toPlainText();
      expect(text, isNot(contains('## 播放')));
      expect(text, contains('## HDR'));
    });

    test('2.3 isEmpty 判定', () {
      expect(const DebugMetrics([]).isEmpty, isTrue);
      expect(
        const DebugMetrics([
          DebugMetricGroup(title: 'x', rows: []),
        ]).isEmpty,
        isTrue,
      );
      expect(
        const DebugMetrics([
          DebugMetricGroup(title: 'x', rows: [DebugMetricRow('a', 'b')]),
        ]).isEmpty,
        isFalse,
      );
    });
  });

  group('3. 状态色语义', () {
    test('3.1 Severity 四档齐全', () {
      expect(Severity.values, hasLength(4));
      expect(Severity.values, contains(Severity.good));
      expect(Severity.values, contains(Severity.warn));
      expect(Severity.values, contains(Severity.error));
      expect(Severity.values, contains(Severity.normal));
    });

    test('3.2 默认 normal', () {
      const r = DebugMetricRow('a', 'b');
      expect(r.severity, Severity.normal);
    });

    test('3.3 关键分组可高亮', () {
      const g = DebugMetricGroup(
        title: 'HDR 输入',
        rows: [DebugMetricRow('a', 'b')],
        highlight: true,
      );
      expect(g.highlight, isTrue);
    });
  });
}

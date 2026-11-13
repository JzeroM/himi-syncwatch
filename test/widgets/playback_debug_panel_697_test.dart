import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';
import 'package:himi_syncwatch/widgets/debug/playback_debug_panel.dart';

/// 697：Flutter 播放调试面板（`PlaybackDebugPanel`）UI 行为。
///
/// ## 为什么用可注入的 metrics 而不是真实采集器
///
/// 面板的职责是**渲染**；采集由 `DebugMetricsCollector` 负责（已有单测）。
/// 直接构造 [DebugMetrics] 能把「分组折叠 / 状态色 / 拖动 / 关闭」这些
/// 纯 UI 行为独立验证，不受 mpv 环境影响。
///
/// ## 关键回归点
///
/// 旧面板（665 行）最大问题是「太乱」——所有内容平铺、无分组、无法折叠。
/// 这里锁定新面板的结构性约束：分组必须存在、必须可折叠、HDR/DV 必须高亮。
void main() {
  /// 构造一份覆盖五个分组的样例指标。
  DebugMetrics sampleMetrics() => const DebugMetrics([
        DebugMetricGroup(
          title: '播放',
          rows: [
            DebugMetricRow('状态', 'PLAYING', severity: Severity.good),
            DebugMetricRow('位置', '00:12 / 00:45'),
            DebugMetricRow('丢帧', '渲染 0 / 解码 0', severity: Severity.good),
          ],
        ),
        DebugMetricGroup(
          title: 'HDR 输入',
          highlight: true,
          rows: [
            DebugMetricRow('色彩', 'bt.2020 / pq', severity: Severity.good),
            DebugMetricRow('位深', '10bit · yuv420p10'),
          ],
        ),
        DebugMetricGroup(
          title: 'HDR 输出',
          highlight: true,
          rows: [
            DebugMetricRow('目标', 'bt.2020 / pq', severity: Severity.good),
            DebugMetricRow('映射', 'bt.2390 (hybrid)', severity: Severity.good),
          ],
        ),
        DebugMetricGroup(
          title: '杜比视界',
          highlight: true,
          rows: [
            DebugMetricRow('Profile', 'P8 L6', severity: Severity.good),
            DebugMetricRow('识别', '已识别为 DV', severity: Severity.good),
          ],
        ),
        DebugMetricGroup(
          title: '渲染管线',
          rows: [
            DebugMetricRow('vo', 'gpu-next'),
            DebugMetricRow('gpu-context', 'd3d11'),
          ],
        ),
      ]);

  /// 面板需要 collector 才能构建，但 UI 测试不触发采集。
  ///
  /// 用一个永远抛错的 collector 不行（会污染日志），所以这里用
  /// `DebugMetrics` 直接喂——见 [PlaybackDebugPanel.metricsOverride]。
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('1. 结构：分组标题与行渲染', () {
    testWidgets('1.1 五个分组标题全部渲染', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('播放'), findsOneWidget);
      expect(find.text('HDR 输入'), findsOneWidget);
      expect(find.text('HDR 输出'), findsOneWidget);
      expect(find.text('杜比视界'), findsOneWidget);
      expect(find.text('渲染管线'), findsOneWidget);
    });

    testWidgets('1.2 指标值渲染', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('bt.2020 / pq'), findsWidgets);
      expect(find.text('bt.2390 (hybrid)'), findsOneWidget);
      expect(find.text('P8 L6'), findsOneWidget);
      expect(find.text('gpu-next'), findsOneWidget);
    });

    testWidgets('1.3 标题显示「播放调试」', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('播放调试'), findsOneWidget);
    });
  });

  group('2. 折叠：点击分组标题收起该组', () {
    testWidgets('2.1 点击后该组行消失，其他组保留', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      // 折叠前：HDR 输入的两行可见
      expect(find.text('10bit · yuv420p10'), findsOneWidget);

      await tester.tap(find.text('HDR 输入'));
      await tester.pumpAndSettle();

      // 折叠后：该组行消失，标题仍在
      expect(find.text('10bit · yuv420p10'), findsNothing);
      expect(find.text('HDR 输入'), findsOneWidget);
      // 其他组不受影响
      expect(find.text('bt.2390 (hybrid)'), findsOneWidget);
    });

    testWidgets('2.2 再点展开恢复', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('HDR 输入'));
      await tester.pumpAndSettle();
      expect(find.text('10bit · yuv420p10'), findsNothing);

      await tester.tap(find.text('HDR 输入'));
      await tester.pumpAndSettle();
      expect(find.text('10bit · yuv420p10'), findsOneWidget);
    });
  });

  group('3. 交互：拖动与关闭', () {
    testWidgets('3.1 拖动标题栏回调 onDrag', (tester) async {
      final deltas = <Offset>[];
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: deltas.add,
          onClose: () {},
        ),
      ));
      await tester.pump();

      // 从标题栏「播放调试」位置拖动
      await tester.drag(find.text('播放调试'), const Offset(30, 20));
      await tester.pumpAndSettle();

      expect(deltas, isNotEmpty);
      // 累计位移应接近拖动量
      final total = deltas.fold<Offset>(
        Offset.zero,
        (sum, d) => sum + d,
      );
      expect(total.dx, greaterThan(0));
    });

    testWidgets('3.2 点关闭按钮回调 onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () => closed = true,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });
  });

  group('4. 视觉：半透明 + 状态色', () {
    testWidgets('4.1 背景半透明 0.72（不是实心黑）', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: sampleMetrics(),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PlaybackDebugPanel),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final color = decoration.color!;
      expect(color.a, closeTo(0.72, 0.01));
    });

    testWidgets('4.2 异常值用红色', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: const DebugMetrics([
            DebugMetricGroup(
              title: '杜比视界',
              highlight: true,
              rows: [
                DebugMetricRow('识别', '未识别', severity: Severity.error),
              ],
            ),
          ]),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('未识别'));
      expect(text.style?.color, const Color(0xFFF87171));
    });

    testWidgets('4.3 正常值用绿色', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: const DebugMetrics([
            DebugMetricGroup(
              title: '播放',
              rows: [
                DebugMetricRow('状态', 'PLAYING', severity: Severity.good),
              ],
            ),
          ]),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('PLAYING'));
      expect(text.style?.color, const Color(0xFF6EE7A0));
    });

    testWidgets('4.4 可疑值用琥珀色', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: const DebugMetrics([
            DebugMetricGroup(
              title: '播放',
              rows: [
                DebugMetricRow('状态', 'PAUSED', severity: Severity.warn),
              ],
            ),
          ]),
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('PAUSED'));
      expect(text.style?.color, const Color(0xFFFBBF24));
    });
  });

  group('5. 空状态', () {
    testWidgets('5.1 空指标不崩溃', (tester) async {
      await tester.pumpWidget(wrap(
        PlaybackDebugPanel(
          metrics: DebugMetrics.empty,
          onDrag: (_) {},
          onClose: () {},
        ),
      ));
      await tester.pump();

      // 标题仍在（面板可用），无分组内容
      expect(find.text('播放调试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

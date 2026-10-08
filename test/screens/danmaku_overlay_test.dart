import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/danmaku_overlay.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_timeline.dart';

DanmakuComment _c(
  double time, {
  String text = '弹幕文本',
  DanmakuMode mode = DanmakuMode.scroll,
  int color = 0xFFFFFFFF,
}) =>
    DanmakuComment(time: time, mode: mode, color: color, text: text);

Future<void> _mount(
  WidgetTester tester, {
  required List<DanmakuComment> comments,
  required ValueNotifier<Duration> position,
  ValueNotifier<bool>? playing,
  DanmakuTimelineConfig config = const DanmakuTimelineConfig(),
  double speed = 1.0,
  double fontSizeScale = 1.0,
  double opacity = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: DanmakuOverlay(
            comments: comments,
            config: config,
            position: position,
            playing: playing ?? ValueNotifier<bool>(true),
            speed: speed,
            fontSizeScale: fontSizeScale,
            opacity: opacity,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('空评论 → 空层不绘制任何文本', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(tester, comments: [], position: position);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Text), findsNothing);
    position.dispose();
  });

  testWidgets('弹幕在出现时间后显示，穿屏时长结束消失', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0.5, text: 'hello')],
      position: position,
    );
    expect(find.byType(Text), findsNothing, reason: '0s < 0.5s 未出现');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('hello'), findsOneWidget, reason: '1s 处于 8s 窗口内');
    // 0.5 + 8 = 8.5s 消失
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(Text), findsNothing);
    position.dispose();
  });

  testWidgets('暂停冻结弹幕、恢复续滚（不跳）', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    final playing = ValueNotifier<bool>(true);
    await _mount(
      tester,
      comments: [_c(0.5, text: 'hello')],
      position: position,
      playing: playing,
    );
    // 模拟进度轮询：位置到 1s（弹幕出现窗口内）
    position.value = const Duration(seconds: 1);
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
    final xBefore = tester.getTopLeft(find.text('hello')).dx;

    // 暂停：Ticker 停走 → 弹幕冻结不动
    playing.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(find.text('hello')).dx, xBefore,
        reason: '暂停期间弹幕必须冻结');

    // 恢复：重锚到位置后继续向左滚动
    playing.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(find.text('hello')).dx, lessThan(xBefore),
        reason: '恢复后弹幕继续滚动');

    position.dispose();
    playing.dispose();
  });

  testWidgets('seek：位置跳变后只显示目标时刻的弹幕', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0.5, text: 'early'), _c(100.5, text: 'late')],
      position: position,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('early'), findsOneWidget);

    position.value = const Duration(seconds: 101);
    await tester.pump();
    expect(find.text('early'), findsNothing, reason: '回退/前进由位置唯一决定');
    expect(find.text('late'), findsOneWidget);
    position.dispose();
  });

  testWidgets('speed=2 穿屏窗口减半', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: 'fast')],
      position: position,
      speed: 2.0,
    );
    await tester.pump(const Duration(milliseconds: 3500));
    expect(find.text('fast'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(Text), findsNothing, reason: '3.5+0.6 > 4s 窗口');
    position.dispose();
  });

  testWidgets('字号倍率作用于 Text 样式', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: 'size')],
      position: position,
      fontSizeScale: 2.0,
    );
    await tester.pump();
    final text = tester.widget<Text>(find.text('size'));
    expect(text.style?.fontSize, DanmakuOverlay.baseFontSize * 2.0);
    position.dispose();
  });

  testWidgets('整体透明度并入字色 alpha（半透明 → alpha 127）', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: 'fade')],
      position: position,
      opacity: 0.5,
    );
    await tester.pump();
    final color = tester.widget<Text>(find.text('fade')).style?.color;
    expect(color, isNotNull);
    expect(color!.a, closeTo(127 / 255, 0.01));
    position.dispose();
  });

  testWidgets('config 屏蔽词生效（时间轴重建）', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: '广告内容'), _c(0, text: '正常')],
      position: position,
      config: const DanmakuTimelineConfig(blockWords: ['广告']),
    );
    await tester.pump();
    expect(find.text('广告内容'), findsNothing);
    expect(find.text('正常'), findsOneWidget);
    position.dispose();
  });

  testWidgets('滚动弹幕 x 随进度从右向左移动', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: 'scroll')],
      position: position,
    );
    await tester.pump(const Duration(seconds: 1));
    final firstLeft = tester.getTopLeft(find.text('scroll')).dx;
    await tester.pump(const Duration(seconds: 3));
    final laterLeft = tester.getTopLeft(find.text('scroll')).dx;
    expect(laterLeft, lessThan(firstLeft), reason: '向左移动');
    position.dispose();
  });

  testWidgets('顶部固定弹幕显示于顶部区域，底部弹幕显示于底部区域', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [
        _c(0, text: 'top', mode: DanmakuMode.top),
        _c(0, text: 'bottom', mode: DanmakuMode.bottom),
      ],
      position: position,
    );
    await tester.pump(const Duration(seconds: 1));
    final topY = tester.getTopLeft(find.text('top')).dy;
    final bottomY = tester.getTopLeft(find.text('bottom')).dy;
    expect(topY, lessThan(100), reason: '顶部区域');
    expect(bottomY, greaterThan(400), reason: '底部区域');
    position.dispose();
  });

  testWidgets('滚动弹幕按屏高自动铺满，行数为上限（配置变更即时重建）', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    final comments = List.generate(10, (i) => _c(0, text: 'row$i'));
    await _mount(
      tester,
      comments: comments,
      position: position,
      config: const DanmakuTimelineConfig(scrollRows: 2),
    );
    await tester.pump();
    expect(find.byType(Text), findsNWidgets(2), reason: '上限 2 → 只保留 2 行');

    // 上限调大 → 同一批弹幕铺满更多行（弹幕层随配置重建）
    await _mount(
      tester,
      comments: comments,
      position: position,
      config: const DanmakuTimelineConfig(scrollRows: 10),
    );
    await tester.pump();
    expect(find.byType(Text), findsNWidgets(10), reason: '上限 10 → 10 行');
    position.dispose();
  });

  testWidgets('弹幕层不拦截手势（IgnorePointer 包裹）', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    await _mount(
      tester,
      comments: [_c(0, text: 'block')],
      position: position,
    );
    await tester.pump();
    expect(find.byType(IgnorePointer), findsWidgets);
    position.dispose();
  });
}

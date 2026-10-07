import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/speed_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/video_gesture_layer.dart';

import '../helpers/test_fakes.dart';

int _verticalDrags = 0;
int _taps = 0;
int _longPressStart = 0;
int _longPressEnd = 0;

/// 模拟 `_buildVideoArea` 修复后结构：VideoGestureLayer 作 Stack 底层
/// （只包视频），倍速浮层面板 Positioned 在上层。
Widget _stack() {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            VideoGestureLayer(
              onTap: () => _taps++,
              onVerticalDragUpdate: (_) => _verticalDrags++,
              child: const Center(child: Text('video')),
            ),
            Positioned(
              top: 40,
              right: 12,
              width: 260,
              bottom: 400,
              child: SelectorSidePanel(
                title: '倍速',
                child: SpeedMenuPanel(current: 1.0, onSelected: (_) {}),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    _verticalDrags = 0;
    _taps = 0;
    _longPressStart = 0;
    _longPressEnd = 0;
  });

  group('VideoGestureLayer + 浮层面板（根因回归）', () {
    testWidgets('拖动面板内 → 面板滚动，视频层纵拖回调不触发', (tester) async {
      await tester.pumpWidget(_stack());

      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(list.position.maxScrollExtent, greaterThan(0),
          reason: '矮浮层内容超高，必须可滚');

      await tester.drag(find.text('0.5x'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
        reason: '面板 ListView 应滚动',
      );
      expect(_verticalDrags, 0, reason: '浮层拖动不得触发音量/亮度视频手势');
      expect(_taps, 0, reason: '拖动不是点击');
    });

    testWidgets('拖动视频空白区 → 触发视频层纵拖回调', (tester) async {
      await tester.pumpWidget(_stack());

      await tester.dragFrom(const Offset(100, 300), const Offset(0, -40));
      await tester.pump();

      expect(_verticalDrags, greaterThan(0), reason: '视频区拖动 = 音量/亮度');
    });

    testWidgets('点视频区触发 onTap；点面板不触发（命中面板即止）', (tester) async {
      await tester.pumpWidget(_stack());

      await tester.tapAt(const Offset(100, 300));
      await tester.pump();
      expect(_taps, 1);

      await tester.tap(find.text('0.75x'));
      await tester.pump();
      expect(_taps, 1, reason: '点面板不应触发视频区点屏手势');
    });
  });

  group('VideoGestureLayer 长按（临时倍速）', () {
    testWidgets('长按触发 onLongPressStart/End，且不触发 onTap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoGestureLayer(
              onTap: () => _taps++,
              onLongPressStart: (_) => _longPressStart++,
              onLongPressEnd: (_) => _longPressEnd++,
              child: const Center(child: Text('video')),
            ),
          ),
        ),
      );

      await tester.longPressAt(const Offset(100, 300));
      await tester.pump();

      expect(_longPressStart, 1, reason: '长按开始应回调');
      expect(_longPressEnd, 1, reason: '松手应回调');
      expect(_taps, 0, reason: '长按不应触发点按');
    });
  });
}

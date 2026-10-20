import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/top_bar_clock_format.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_clock.dart';

void main() {
  group('formatPlayerClock', () {
    test('24 小时制补零', () {
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 0, 0),
          TopBarClockFormat.twentyFourHour,
        ),
        '00:00',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 9, 5),
          TopBarClockFormat.twentyFourHour,
        ),
        '09:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 13, 5),
          TopBarClockFormat.twentyFourHour,
        ),
        '13:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 23, 59),
          TopBarClockFormat.twentyFourHour,
        ),
        '23:59',
      );
    });

    test('12 小时制使用上午/下午且小时不补零', () {
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 0, 5),
          TopBarClockFormat.twelveHour,
        ),
        '上午 12:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 9, 5),
          TopBarClockFormat.twelveHour,
        ),
        '上午 9:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 12, 5),
          TopBarClockFormat.twelveHour,
        ),
        '下午 12:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 14, 5),
          TopBarClockFormat.twelveHour,
        ),
        '下午 2:05',
      );
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 23, 59),
          TopBarClockFormat.twelveHour,
        ),
        '下午 11:59',
      );
    });

    test('关闭返回空串', () {
      expect(
        formatPlayerClock(
          DateTime(2026, 1, 1, 14, 5),
          TopBarClockFormat.off,
        ),
        '',
      );
    });
  });

  testWidgets('时钟层仅 TV 模式显示，且不随控制栏显隐', (tester) async {
    var showControls = false;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return Stack(
                children: [
                  if (showControls)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Text('controls'),
                    ),
                  PlayerClockLayer(
                    format: TopBarClockFormat.twelveHour,
                    tvMode: true,
                    now: () => DateTime(2026, 1, 1, 14, 5),
                    autoTick: false,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('playerClock')), findsOneWidget);
    expect(find.text('controls'), findsNothing);

    setState(() => showControls = true);
    await tester.pump();
    expect(find.text('controls'), findsOneWidget);
    expect(find.byKey(const ValueKey('playerClock')), findsOneWidget);
  });

  testWidgets('非 TV 模式时钟层为空', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PlayerClockLayer(
                format: TopBarClockFormat.twelveHour,
                tvMode: false,
                autoTick: false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('playerClock')), findsNothing);
  });

  testWidgets('时钟层位于顶栏最右侧', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                PlayerClockLayer(
                  format: TopBarClockFormat.twelveHour,
                  tvMode: true,
                  now: () => DateTime(2026, 1, 1, 14, 5),
                  autoTick: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('playerClock')));
    expect(rect.right, closeTo(788, 0.5));
  });

  testWidgets('关闭时时钟层为空', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PlayerClockLayer(
                format: TopBarClockFormat.off,
                tvMode: true,
                autoTick: false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('playerClock')), findsNothing);
  });

  testWidgets('固定时间渲染 12 小时制', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerClock(
          format: TopBarClockFormat.twelveHour,
          now: () => DateTime(2026, 1, 1, 14, 5),
          autoTick: false,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('playerClock')), findsOneWidget);
    expect(find.text('下午 2:05'), findsOneWidget);
  });

  testWidgets('到下一分钟自动刷新', (tester) async {
    var now = DateTime(2026, 1, 1, 14, 5);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerClock(
          format: TopBarClockFormat.twelveHour,
          now: () => now,
        ),
      ),
    );
    expect(find.text('下午 2:05'), findsOneWidget);

    now = DateTime(2026, 1, 1, 14, 6);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.text('下午 2:06'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

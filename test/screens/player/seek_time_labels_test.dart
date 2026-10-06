import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/seek_time_labels.dart';

void main() {
  group('formatPlayerDuration', () {
    test('无小时时为 MM:SS（补零）', () {
      expect(formatPlayerDuration(Duration.zero), '00:00');
      expect(formatPlayerDuration(const Duration(seconds: 5)), '00:05');
      expect(formatPlayerDuration(const Duration(seconds: 105)), '01:45');
    });

    test('有小时时为 HH:MM:SS（补零）', () {
      expect(formatPlayerDuration(const Duration(minutes: 65)), '01:05:00');
      expect(
        formatPlayerDuration(const Duration(hours: 1, minutes: 39, seconds: 2)),
        '01:39:02',
      );
      expect(
        formatPlayerDuration(const Duration(hours: 12, minutes: 5, seconds: 3)),
        '12:05:03',
      );
      expect(
        formatPlayerDuration(
            const Duration(hours: 100, minutes: 1, seconds: 1)),
        '100:01:01',
      );
    });
  });

  group('SeekTimeLabels', () {
    test('cellWidth：<1h 为 56，≥1h 为 78（供播放控件对齐左数显）', () {
      expect(SeekTimeLabels.cellWidth(const Duration(minutes: 59, seconds: 59)),
          56.0);
      expect(SeekTimeLabels.cellWidth(const Duration(hours: 1)), 78.0);
      expect(
          SeekTimeLabels.cellWidth(const Duration(hours: 2, minutes: 5)), 78.0);
    });

    Widget wrap(Duration pos, Duration dur) => MaterialApp(
          home: Scaffold(
            body: SeekTimeLabels(
              position: pos,
              duration: dur,
              child: const Slider(value: 0.1, onChanged: null),
            ),
          ),
        );

    testWidgets('左进度右总长，数显拆开放在进度条两侧', (tester) async {
      await tester.pumpWidget(wrap(
        const Duration(minutes: 1, seconds: 45),
        const Duration(hours: 1, minutes: 39, seconds: 2),
      ));

      expect(find.text('01:45'), findsOneWidget, reason: '左侧当前进度');
      expect(find.text('01:39:02'), findsOneWidget, reason: '右侧总时长');

      final sliderCenter = tester.getCenter(find.byType(Slider));
      final left = tester.getCenter(find.text('01:45'));
      final right = tester.getCenter(find.text('01:39:02'));
      expect(left.dx, lessThan(sliderCenter.dx), reason: '进度在滑杆左侧');
      expect(right.dx, greaterThan(sliderCenter.dx), reason: '总长在滑杆右侧');

      // 与滑杆同一水平中线（Row 垂直居中）
      expect(left.dy, closeTo(sliderCenter.dy, 8));
      expect(right.dy, closeTo(sliderCenter.dy, 8));
    });

    testWidgets('左右两格同宽，逐秒更新不产生布局位移', (tester) async {
      await tester.pumpWidget(wrap(
        const Duration(minutes: 1, seconds: 45),
        const Duration(minutes: 9, seconds: 59),
      ));
      final before = tester.getSize(find.text('01:45'));

      // 进度跨分钟位数变化（09:59 → 10:00）
      await tester.pumpWidget(wrap(
        const Duration(minutes: 10),
        const Duration(minutes: 9, seconds: 59),
      ));
      final after = tester.getSize(find.text('10:00'));

      expect(after.width, before.width, reason: '左格宽度固定不抖动');
      // 右格与左格同宽
      expect(
        tester.getSize(find.text('09:59')).width,
        after.width,
      );
    });

    testWidgets('小时档：两格加宽适配 HH:MM:SS', (tester) async {
      await tester.pumpWidget(wrap(
        const Duration(minutes: 45),
        const Duration(minutes: 59, seconds: 59),
      ));
      final mmWidth = tester.getSize(find.text('45:00')).width;

      await tester.pumpWidget(wrap(
        const Duration(hours: 1, minutes: 45),
        const Duration(hours: 1, minutes: 59, seconds: 59),
      ));
      final hhWidth = tester.getSize(find.text('01:45:00')).width;

      expect(hhWidth, greaterThan(mmWidth), reason: '小时档更宽');
      expect(
        tester.getSize(find.text('01:59:59')).width,
        hhWidth,
        reason: '小时档左右同宽',
      );
    });
  });
}

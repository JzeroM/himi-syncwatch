import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/segment_mark_panel.dart';

import '../helpers/test_fakes.dart';

void main() {
  testWidgets('标记面板显示当前位置与已有标记，点击回传类型', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    MediaSegmentType? selected;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SegmentMarkPanel(
              positionMs: 65000,
              introEndMs: null,
              creditsStartMs: 90000,
              firstFocusNode: focusNode,
              onSelect: (type) => selected = type,
            ),
          ),
        ),
      ),
    );

    expect(find.text('当前位置 1:05'), findsOneWidget);
    expect(find.text('设置片头'), findsOneWidget);
    expect(find.text('设置片尾'), findsOneWidget);
    expect(find.text('已设置：1:30'), findsOneWidget);

    await tester.tap(find.text('设置片头'));
    expect(selected, MediaSegmentType.intro);
  });

  testWidgets('范围约束：片头超 10% / 片尾低于 70% 时行内红字提示（588）',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    const durationMs = 3600000; // 60 分钟

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SegmentMarkPanel(
              positionMs: 1800000, // 30 分钟：片头越界、片尾也未到 70%
              durationMs: durationMs,
              introEndMs: null,
              creditsStartMs: null,
              firstFocusNode: focusNode,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('片头结束点不能超过总时长的 10%'), findsOneWidget);
    expect(find.text('片尾开始点不能低于总时长的 70%'), findsOneWidget);
    // 原提示文案被替换（不会同时出现）。
    expect(find.text('当前位置作为片头结束 / 正片开始'), findsNothing);
  });

  testWidgets('范围约束：合法位置显示原提示（不误报）', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SegmentMarkPanel(
              positionMs: 300000, // 5 分钟：片头合法（<10%）
              durationMs: 3600000,
              introEndMs: null,
              creditsStartMs: null,
              firstFocusNode: focusNode,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('当前位置作为片头结束 / 正片开始'), findsOneWidget);
    // 片尾在 5 分钟处仍越界。
    expect(find.text('片尾开始点不能低于总时长的 70%'), findsOneWidget);
  });
}

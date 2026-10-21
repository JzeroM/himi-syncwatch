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
}

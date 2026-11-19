import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';

import '../helpers/test_fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/media_info_summary.dart';
import 'package:himi_syncwatch/widgets/media_badge_row.dart';
import 'package:himi_syncwatch/widgets/video_info_sheet.dart';

/// 695：媒体徽章行 + 视频详细信息面板渲染行为。
void main() {
  testWidgets('徽章行：逐胶囊渲染、右对齐布局；空徽章不占位', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings())),
      ],
      
      child: MaterialApp(
        home: Scaffold(
          body: MediaBadgeRow(badges: ['4K', 'DV P5', '20.50G']),
        ),
      ),
    ));
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('DV P5'), findsOneWidget);
    expect(find.text('20.50G'), findsOneWidget);

    final row = tester.widget<Row>(
        find.descendant(of: find.byType(MediaBadgeRow), matching: find.byType(Row)));
    expect(row.mainAxisAlignment, MainAxisAlignment.end, reason: '右对齐');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings())),
      ],
      
      child: MaterialApp(home: Scaffold(body: MediaBadgeRow(badges: []))),
    ));
    expect(find.byType(Text), findsNothing, reason: '空徽章不渲染');
  });

  testWidgets('详情面板：分组玻璃卡片、每条信息纵向独占一行', (tester) async {
    const summary = MediaInfoSummary(
      badges: ['4K'],
      groups: [
        MediaInfoGroup(title: '文件', rows: [
          MediaInfoRow(label: '文件名', value: 'movie.mkv'),
          MediaInfoRow(label: '大小', value: '15.210 GiB'),
        ]),
        MediaInfoGroup(title: '音频', rows: [
          MediaInfoRow(label: '声道', value: '2'),
        ]),
      ],
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VideoInfoSheet(summary: summary)),
    ));
    await tester.pump();

    expect(find.text('视频详细信息'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('movie.mkv'), findsOneWidget);
    expect(find.text('15.210 GiB'), findsOneWidget);
    expect(find.text('声道'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // 每条信息一行：行数 = 标签数 = 值数
    expect(find.textContaining('文件名').evaluate().length, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/version_preference.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/appearance_settings_screen.dart';

import '../helpers/test_fakes.dart';

void main() {
  testWidgets('外观设置：视频版本偏好面板上移并保存', (tester) async {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppearanceSettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 外观页内容较长，ListView 懒构建 → 先滚动到入口
    final entry = find.byKey(const ValueKey('versionPreferenceEntry'));
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('视频版本偏好'), findsWidgets);
    expect(find.byKey(const ValueKey('versionPrefRow_highBitrate')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('versionPrefRow_sdr')), findsOneWidget);
    // v1.1.233 移除「由服务决定」维度
    expect(find.text('由服务决定'), findsNothing);
    expect(find.byKey(const ValueKey('versionPrefRow_serverDefault')),
        findsNothing);

    // 上移最后一项 sdr → 使其位于 lowBitrate 之上
    await tester.tap(find.byKey(const ValueKey('versionPrefUp_sdr')));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('versionPrefRow_sdr'))).top,
      lessThan(tester
          .getRect(find.byKey(const ValueKey('versionPrefRow_lowBitrate')))
          .top),
    );

    await tester.tap(find.byKey(const ValueKey('versionPrefConfirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final order = container.read(settingsProvider).versionPreferenceOrder;
    expect(order.indexOf(VersionPreference.sdr),
        order.indexOf(VersionPreference.lowBitrate) - 1,
        reason: '确定后 sdr 已上移到 lowBitrate 之前并落盘');
  });
}

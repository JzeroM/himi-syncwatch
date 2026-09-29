import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  FakeAgoraConfigNotifier? agora,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      agoraConfigProvider
          .overrideWith((ref) => agora ?? FakeAgoraConfigNotifier()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AgoraConfigScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未配置时显示未配置状态', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('填写 App ID 后即可开房与加入房间'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsNothing);
  });

  testWidgets('App ID 为空时保存被拒绝', (tester) async {
    final container = await _pumpScreen(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(container.read(agoraConfigProvider), isNull);
    expect(find.text('App ID 不能为空'), findsOneWidget);
    await _settleSnackbars(tester);
  });

  testWidgets('填写 App ID 与证书后保存成功', (tester) async {
    final container = await _pumpScreen(tester);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 32);
    await tester.enterText(find.byType(TextField).at(1), 'certificate');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final config = container.read(agoraConfigProvider);
    expect(config, isNotNull);
    expect(config!.isConfigured, isTrue);
    expect(config.appId, 'a' * 32);
    expect(find.text('已配置'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsOneWidget);
    await _settleSnackbars(tester);
  });

  testWidgets('清空后回到未配置状态', (tester) async {
    final agora = FakeAgoraConfigNotifier();
    await _pumpScreen(tester, agora: agora);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 32);
    await tester.enterText(find.byType(TextField).at(1), 'certificate');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await _settleSnackbars(tester);

    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('未配置'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsNothing);
    await _settleSnackbars(tester);
  });

  testWidgets('配置说明按钮打开引导弹窗', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('配置说明'));
    await tester.pumpAndSettle();

    expect(find.text('步骤 1: 注册登录并创建通用项目'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}

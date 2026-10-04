import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  FakeAgoraConfigNotifier? agora,
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
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

  testWidgets('无扫码入口（声网仅手动配置，非 TV 同样无）', (tester) async {
    await _pumpScreen(tester);

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });

  testWidgets('TV 模式同样无扫码入口', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
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

  testWidgets('引导弹窗内图片放大可用「关闭」按钮退出', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('配置说明'));
    await tester.pumpAndSettle();

    // 3.47 起测试环境 asset decode 为真实异步，pumpAndSettle 等不到 →
    // runAsync 预缓存步骤图，否则 Image 宽为 0，tap 必 miss。
    final ctx = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/agora_step1.png'), ctx));
    await tester.pumpAndSettle();

    // 点步骤图 → 图片放大弹窗（此前只有点图手势，遥控器进不去）
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsNWidgets(2), reason: '放大弹窗关闭 + 引导弹窗关闭');

    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsOneWidget, reason: '放大弹窗已关');
    expect(find.text('步骤 1: 注册登录并创建通用项目'), findsOneWidget);
  });

  testWidgets('已配置时默认收起表单，点编辑按钮展开', (tester) async {
    await _pumpScreen(
      tester,
      agora: FakeAgoraConfigNotifier(
        AgoraConfigModel(appId: 'a' * 32, appCertificate: 'certificate'),
      ),
    );

    // 默认收起：无输入框与保存按钮，状态卡带编辑按钮
    expect(find.text('已配置'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.byKey(const ValueKey('agoraEditButton')), findsOneWidget);
    // 配置说明 / 清空始终可见
    expect(find.widgetWithText(TextButton, '清空'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agoraEditButton')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('编辑后保存成功自动收起表单', (tester) async {
    final agora = FakeAgoraConfigNotifier(
      AgoraConfigModel(appId: 'a' * 32, appCertificate: 'old_cert'),
    );
    await _pumpScreen(tester, agora: agora);

    await tester.tap(find.byKey(const ValueKey('agoraEditButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'new_cert');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(agora.state?.appCertificate, 'new_cert');
    expect(find.byType(TextField), findsNothing);
    await _settleSnackbars(tester);
  });
}

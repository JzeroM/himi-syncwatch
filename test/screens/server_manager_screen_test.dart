import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server({
  required String id,
  required String name,
  required String serverId,
}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: name,
    serverId: serverId,
    username: 'user',
    accessToken: 'token',
    userId: 'uid',
  );
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  List<EmbyServerConfig> servers = const [],
  FakeEmbyAuthService? auth,
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider
          .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServerListProvider
          .overrideWith((ref) => EmbyServerListNotifier()..setList(servers)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ServerManagerScreen()),
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
  testWidgets('空列表显示引导提示', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Emby 服务器'), findsOneWidget);
    expect(find.text('暂无服务器\n点击右上角 + 添加'), findsOneWidget);
  });

  testWidgets('展示服务器列表并标记当前服务器', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    expect(find.text('家庭NAS'), findsOneWidget);
    expect(find.text('备用服务器'), findsOneWidget);
  });

  testWidgets('点击未激活服务器完成切换', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_b');
    expect(auth.selectedServerId, 'srv_b');
    await _settleSnackbars(tester);
  });

  testWidgets('扫码图标进入手机配置页（仅 TV 模式显示）', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));

    await tester.tap(find.byTooltip('手机扫码配置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(QrConfigScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(QrConfigScreen), findsNothing);
  });

  testWidgets('非 TV 模式隐藏扫码入口（手动输入服务器）', (tester) async {
    await _pumpScreen(tester);

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    // 手动添加入口不受影响
    expect(find.byTooltip('添加服务器'), findsOneWidget);
  });

  testWidgets('点击 + 展开添加服务器表单', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byTooltip('添加服务器'));
    await tester.pumpAndSettle();

    expect(find.text('连接并登录'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
  });
}

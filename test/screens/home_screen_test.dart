import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

import '../helpers/test_fakes.dart';

Map<String, dynamic> _sessionJson({
  required String id,
  required String serverId,
  required String serverUrl,
}) {
  return {
    'id': id,
    'serverId': serverId,
    'serverUrl': serverUrl,
    'serverName': '家庭NAS',
    'userId': 'uid',
    'username': 'user',
    'accessToken': 'token',
  };
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  FakeEmbyAuthService? auth,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyAuthServiceProvider.overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('无服务器时显示引导到 Emby 服务器标签的空态', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('暂无服务器'), findsOneWidget);
    expect(
      find.text('请到「Emby服务器」标签添加 Emby 服务器'),
      findsOneWidget,
    );
  });

  testWidgets('不再使用侧边栏与菜单按钮', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(Drawer), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('顶栏使用玻璃背景', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(GlassBackdrop), findsOneWidget);
    expect(find.text('HIMI'), findsOneWidget);
  });

  testWidgets('已有服务器时加载媒体库且不报错', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final container = await _pumpScreen(tester, auth: auth);

    expect(container.read(embyConfigProvider)?.serverName, '家庭NAS');
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}

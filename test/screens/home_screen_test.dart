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
  String name = '家庭NAS',
}) {
  return {
    'id': id,
    'serverId': serverId,
    'serverUrl': serverUrl,
    'serverName': name,
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

/// 包裹指定图标的玻璃容器（椭圆胶囊）。
Finder _capsuleOf(IconData icon) => find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(GlassContainer),
    );

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

  testWidgets('顶栏无通栏玻璃条，仅标题与操作两个玻璃椭圆', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(GlassBackdrop), findsNothing);
    expect(find.byType(GlassContainer), findsNWidgets(2));
    expect(find.text('HIMI'), findsOneWidget);
    // 空态标题同样被玻璃椭圆包裹
    expect(_capsuleOf(Icons.dns_outlined), findsOneWidget);
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

  testWidgets('标题显示当前服务器名并可下拉切换', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1', 's2'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
        's2': _sessionJson(
          id: 'srv_b',
          serverId: 's2',
          serverUrl: 'https://b',
          name: '备用服务器',
        ),
      },
    );
    final container = await _pumpScreen(tester, auth: auth);

    // 标题为当前服务器名
    expect(find.text('家庭NAS'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    // 点击标题弹出服务器下拉
    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();
    expect(find.text('备用服务器'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);

    // 选择另一台服务器完成切换
    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_b');
    expect(auth.selectedServerId, 'srv_b');
    expect(find.text('备用服务器'), findsOneWidget);
  });

  testWidgets('服务器标题与顶部操作按钮各包进玻璃椭圆', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(tester, auth: auth);

    // 标题（服务器名）被玻璃椭圆包裹
    expect(_capsuleOf(Icons.dns_outlined), findsOneWidget);
    expect(_capsuleOf(Icons.arrow_drop_down), findsOneWidget);

    // 搜索 / 加入房间 / 开房间三个按钮同属一个玻璃椭圆
    final search = tester.widgetList(_capsuleOf(Icons.search)).first;
    final join = tester.widgetList(_capsuleOf(Icons.group_add)).first;
    final room =
        tester.widgetList(_capsuleOf(Icons.add_circle_outline)).first;
    expect(identical(search, join), isTrue);
    expect(identical(room, join), isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/room_resource_search.dart';
import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server(String id, String name) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.example.com',
      serverName: name,
      serverId: 'srv-$id',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

MediaItem _item(String id, String name) =>
    MediaItem(id: id, name: name, type: 'Movie', posterUrl: '');

/// 记录 flutter/platform 的方向/系统 UI 调用序列。
final List<MethodCall> _platformLog = [];

void _mockPlatformChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    _platformLog.add(call);
    return null;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

List<String> _orientationsOf(MethodCall call) =>
    (call.arguments as List).cast<String>();

String _uiModeOf(MethodCall call) => call.arguments as String;

/// 方向类调用（过滤框架自身的 overlay/sound 等杂音）。
List<MethodCall> _orientCalls() => _platformLog
    .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
    .toList();

List<MethodCall> _uiCalls() => _platformLog
    .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
    .toList();

Future<void> _pumpRoomHarness(WidgetTester tester) async {
  _platformLog.clear();
  _mockPlatformChannel();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServerListProvider.overrideWith(
        (ref) => EmbyServerListNotifier()..setList([_server('a', '服务器甲')]),
      ),
      globalSearchProvider.overrideWithValue(
        GlobalSearchService(
          serviceFactory: (_) => FakeEmbyService(
            searchResults: [_item('a1', '甲的影片')],
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _PanelPage()),
      GoRoute(
        path: '/detail/:id',
        builder: (_, state) => _FakeDetailPage(state: state),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 资源面板替身：调 pushRoomResourceSearch 并接收返回的资源数据。
class _PanelPage extends StatefulWidget {
  const _PanelPage();

  @override
  State<_PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<_PanelPage> {
  Object? _received;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('资源面板'),
          ElevatedButton(
            key: const ValueKey('openRoomSearch'),
            onPressed: () async {
              final data = await pushRoomResourceSearch(
                context,
                roomCode: 'rc1',
              );
              if (data != null && mounted) {
                setState(() => _received = data);
              }
            },
            child: const Text('打开搜索'),
          ),
          if (_received != null) Text('received:$_received'),
        ],
      ),
    );
  }
}

/// roomMode 详情替身：展示 query 参数；返回资源数据或 null。
class _FakeDetailPage extends StatelessWidget {
  const _FakeDetailPage({required this.state});

  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('detail:${state.pathParameters['id']}'),
          Text('query:${state.uri.query}'),
          ElevatedButton(
            key: const ValueKey('returnResource'),
            onPressed: () => Navigator.of(context).pop({'resourceId': 'r1'}),
            child: const Text('返回资源'),
          ),
          ElevatedButton(
            key: const ValueKey('returnNull'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('直接返回'),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('进入：先竖屏后开搜索页（portraitUp → edgeToEdge）', (tester) async {
    await _pumpRoomHarness(tester);

    await tester.tap(find.byKey(const ValueKey('openRoomSearch')));
    await tester.pump(); // 函数同步段已执行，push 转场中

    expect(_orientCalls(), hasLength(1), reason: '进入只发一条方向指令');
    expect(_orientationsOf(_orientCalls().single),
        [DeviceOrientation.portraitUp.toString()]);
    expect(_uiCalls(), hasLength(1));
    expect(_uiModeOf(_uiCalls().single), SystemUiMode.edgeToEdge.toString());

    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchScreen), findsOneWidget);
  });

  testWidgets('全链路：竖屏搜片挑资源返回 → 数据带回面板 + 恢复横屏', (tester) async {
    await _pumpRoomHarness(tester);

    await tester.tap(find.byKey(const ValueKey('openRoomSearch')));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posterCard_a1_a')));
    await tester.pumpAndSettle();

    // roomMode 详情带全参数
    expect(find.text('detail:a1'), findsOneWidget);
    expect(
      find.textContaining('roomMode=true').evaluate().single,
      isNotNull,
    );
    expect(find.textContaining('roomCode=rc1').evaluate().single, isNotNull);
    expect(find.textContaining('server=a').evaluate().single, isNotNull);

    await tester.tap(find.byKey(const ValueKey('returnResource')));
    await tester.pumpAndSettle();

    expect(find.text('received:{resourceId: r1}'), findsOneWidget,
        reason: '资源数据带回面板');
    expect(find.byType(GlobalSearchScreen), findsNothing, reason: '搜索页已退场');

    // 尾部序列：恢复沉浸 + 横屏
    expect(_uiCalls().length, 2, reason: '进入 edgeToEdge + 退出 immersiveSticky');
    expect(_uiModeOf(_uiCalls().last), SystemUiMode.immersiveSticky.toString());
    expect(_orientCalls().length, 2, reason: '进入竖屏 + 退出横屏');
    expect(_orientationsOf(_orientCalls().last),
        [DeviceOrientation.landscapeLeft.toString()]);
  });

  testWidgets('详情未选资源返回：留在搜索页继续挑（保持竖屏），退出才恢复', (tester) async {
    await _pumpRoomHarness(tester);

    await tester.tap(find.byKey(const ValueKey('openRoomSearch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posterCard_a1_a')));
    await tester.pumpAndSettle();

    final logAfterOrient = _orientCalls().length;
    await tester.tap(find.byKey(const ValueKey('returnNull')));
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchScreen), findsOneWidget, reason: '留在搜索页继续挑');
    expect(_orientCalls().length, logAfterOrient, reason: '未退出竖屏窗口，无新方向指令');
    expect(find.text('received:null').evaluate(), isEmpty, reason: '面板未收到数据');

    // 用户返回面板 → 恢复横屏
    await tester.tap(find.byKey(const ValueKey('globalSearchBack')));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchScreen), findsNothing);
    expect(_orientationsOf(_orientCalls().last),
        [DeviceOrientation.landscapeLeft.toString()]);
    expect(_uiModeOf(_uiCalls().last), SystemUiMode.immersiveSticky.toString());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/shell/shell_back_intercept_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';

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

/// 完整壳层（真实 appRouter）+ 注入服务器，进入 Emby 页。
/// [useTvTopNav]=true 时走 TV 顶栏导航直接切到 Emby（无底部胶囊）。
Future<ProviderContainer> _pumpShellOnServers(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
  List<Map<String, dynamic>> sessions = const [],
  bool useTvTopNav = false,
}) async {
  final serverIds = [for (final s in sessions) s['serverId'] as String];
  final sessionMap = {for (final s in sessions) s['serverId'] as String: s};

  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider.overrideWith(
        (ref) => FakeEmbyAuthService(
          serverIds: serverIds,
          sessions: sessionMap,
        ),
      ),
      embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
      tvDiscoveryProvider.overrideWith((ref) => FakeTvDiscoveryNotifier()),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize =
      useTvTopNav ? const Size(960, 540) : const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(appRouterProvider),
      ),
    ),
  );
  // 首页 _init 异步加载服务器列表，推进帧让它完成
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  if (useTvTopNav) {
    // TV 顶栏 TvFocusable 是键盘焦点驱动，直接路由跳到 Emby 页更稳
    container.read(appRouterProvider).go('/servers');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    // 手机底部胶囊：先点胶囊唤醒，再点 Emby 图标（选中态可能是实心 dns）
    await tester.tap(find.byKey(const ValueKey('shellNavBarPadding')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final embyIcon = find.descendant(
      of: find.byKey(const ValueKey('shellNavBarPadding')),
      matching: find.byIcon(kShellNavIcons[2]),
    );
    final embyIconSelected = find.descendant(
      of: find.byKey(const ValueKey('shellNavBarPadding')),
      matching: find.byIcon(kShellNavSelectedIcons[2]),
    );
    await tester
        .tap(embyIcon.evaluate().isNotEmpty ? embyIcon : embyIconSelected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(find.byType(ServerManagerScreen), findsOneWidget,
      reason: '应已进入 Emby 服务器页');
  return container;
}

Future<void> _settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// 模拟 TV 遥控器长按 OK（按下 → 600ms → 松开）。
Future<void> _pressLongOk(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('壳层：表单开按返回 → 关表单留在 Emby 页，不跳首页（v1.1.244）',
      (tester) async {
    await _pumpShellOnServers(
      tester,
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      ],
    );

    // 点 + 展开添加表单
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('连接并登录'), findsOneWidget, reason: '表单已展开');

    // 系统返回 → 关表单，留在 Emby 页
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('连接并登录'), findsNothing, reason: '返回应关闭表单');
    expect(find.byType(ServerManagerScreen), findsOneWidget,
        reason: '关表单后仍留在 Emby 页');
    expect(find.byType(HomeScreen), findsNothing, reason: '不应跳回首页');
  });

  testWidgets('壳层：表单关闭后再按返回 → 回首页 tab（v1.1.244）', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpShellOnServers(
      tester,
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      ],
    );

    // 展开表单 → 返回关闭
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ServerManagerScreen), findsOneWidget);

    // 再按返回 → 回首页 tab
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeScreen), findsOneWidget, reason: '再按应回首页');
    expect(find.byType(ServerManagerScreen), findsNothing);
    final exited =
        calls.any((c) => c.method == 'SystemNavigator.pop');
    expect(exited, isFalse, reason: '回首页不退桌面');
  });

  testWidgets('壳层：编辑表单开按返回 → 关编辑表单留在 Emby 页（v1.1.244）',
      (tester) async {
    await _pumpShellOnServers(
      tester,
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      ],
    );

    // 打开 ⋮ 菜单 → 编辑
    await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑服务器'), findsOneWidget, reason: '编辑表单已展开');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('编辑服务器'), findsNothing, reason: '返回应关闭编辑表单');
    expect(find.byType(ServerManagerScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await _settleSnackbars(tester);
  });

  testWidgets('壳层：⋮ 面板展开按返回 → 关面板留 Emby 页且焦点回 ⋮（v1.2.4）',
      (tester) async {
    await _pumpShellOnServers(
      tester,
      settings: const AppSettings(tvMode: true),
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      ],
      useTvTopNav: true,
    );

    // 打开 ⋮ 操作面板
    await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
    await tester.pumpAndSettle();
    expect(find.text('切换线路'), findsOneWidget, reason: '操作面板已展开');
    expect(find.text('删除'), findsOneWidget, reason: '操作面板含删除项');

    // 系统返回 → 关面板，留在 Emby 页，焦点回 ⋮
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('切换线路'), findsNothing, reason: '返回应关闭操作面板');
    expect(find.text('删除'), findsNothing, reason: '返回应关闭操作面板');
    expect(find.byType(ServerManagerScreen), findsOneWidget,
        reason: '关面板后仍留在 Emby 页');
    expect(find.byType(HomeScreen), findsNothing, reason: '不应跳回首页');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'serverMoreBtn',
        reason: '面板关闭后焦点应回到三个点');
    await _settleSnackbars(tester);
  });

  testWidgets('壳层：TV 布局模式按返回 → 取消布局留在 Emby 页（v1.1.244）',
      (tester) async {
    final container = await _pumpShellOnServers(
      tester,
      settings: const AppSettings(tvMode: true),
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
        _sessionJson(
            id: 'srv_b',
            serverId: 's2',
            serverUrl: 'https://b',
            name: '备用服务器'),
      ],
      // TV 用顶部导航，直接落在 Emby 页
      useTvTopNav: true,
    );

    // 长按 OK 进布局模式
    await _pressLongOk(tester);
    expect(find.text('移动中'), findsOneWidget, reason: '应进入布局模式');

    // 返回键 → 取消布局，留在 Emby 页
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _settleSnackbars(tester);

    expect(find.text('移动中'), findsNothing, reason: '返回应取消布局模式');
    expect(find.byType(ServerManagerScreen), findsOneWidget,
        reason: '取消布局后仍留在 Emby 页');
    expect(find.byType(HomeScreen), findsNothing);
    expect(
      container.read(embyServerListProvider).map((s) => s.id).toList(),
      ['srv_a', 'srv_b'],
      reason: '取消应还原顺序',
    );
  });

  testWidgets('拦截器：无活跃状态时 provider 为 null，壳层走默认返回', (tester) async {
    final container = await _pumpShellOnServers(
      tester,
      sessions: [
        _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      ],
    );
    expect(container.read(shellBackInterceptProvider), isNull,
        reason: '无表单/布局时不应注册拦截');
  });
}

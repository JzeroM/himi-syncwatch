import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/room/qr_scanner_screen.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';
import 'package:himi_syncwatch/screens/shell/main_shell.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

EmbyServerConfig _serverConfig(String id, {String? name}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: name ?? '服务器$id',
    serverId: 'srv-$id',
    username: 'user',
    accessToken: 'token',
    userId: 'uid',
  );
}

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  FakeEmbyAuthService? auth,
  FakeEmbyService? emby,
  EdgeInsets viewPadding = EdgeInsets.zero,
  AppSettings settings = const AppSettings(),
  List<EmbyServerConfig> serverList = const [],
  EmbyServerConfig? currentServer,
  GlobalSearchService? globalSearch,
}) async {
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
        embyAuthServiceProvider
            .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
        embyServiceProvider.overrideWith((ref) => emby ?? FakeEmbyService()),
        if (serverList.isNotEmpty)
          embyServerListProvider.overrideWith(
            (ref) => EmbyServerListNotifier()..setList(serverList),
          ),
        if (currentServer != null)
          embyConfigProvider.overrideWith(
            (ref) => EmbyConfigNotifier()..setConfig(currentServer),
          ),
        if (globalSearch != null)
          globalSearchProvider.overrideWithValue(globalSearch),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          // 与生产（core/app.dart）一致：提供 GlassBackgroundSource 所需的采样键
          return lg.LiquidGlassScope(
            child: MaterialApp.router(
              routerConfig: router,
              // 模拟真机系统栏（edge-to-edge 下 padding 已被消费，仅 viewPadding 保留）
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(viewPadding: viewPadding),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Map<String, dynamic> _sessionJson({String id = 's1'}) => {
      'id': id,
      'serverId': id,
      'serverUrl': 'https://$id.example',
      'serverName': '家庭NAS',
      'userId': 'uid',
      'username': 'user',
      'accessToken': 'token',
    };

/// 首页有 4 个媒体库可滚动（posterUrl 为 null，不触发图片加载动画）。
FakeEmbyService _scrollableEmby() => FakeEmbyService(
      libraries: List.generate(
        4,
        (i) => LibraryFolder(
          id: 'lib$i',
          name: '媒体库$i',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ),
      items: List.generate(
        12,
        (i) => MediaItem(id: 'm$i', name: '影片$i', type: 'Movie'),
      ),
    );

double _navOpacity(WidgetTester tester) {
  final opacities = tester.widgetList<AnimatedOpacity>(
    find.descendant(
      of: find.byType(MainShell),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  // 导航显隐的 AnimatedOpacity 是第一个且唯一带 300ms 的
  return opacities
      .firstWhere(
        (o) => o.duration == const Duration(milliseconds: 300),
        orElse: () => opacities.first,
      )
      .opacity;
}

int _shellIndex(WidgetTester tester) {
  final stack = tester.widget<IndexedStack>(
    find
        .descendant(
          of: find.byType(MainShell),
          matching: find.byType(IndexedStack),
        )
        .first,
  );
  return stack.index!;
}

void main() {
  testWidgets('默认进入首页，壳提供四个标签且无侧边栏', (tester) async {
    await _pumpApp(tester);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('Emby服务器'), findsOneWidget);
    expect(find.text('声网配置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(_shellIndex(tester), 0);
  });

  testWidgets('点击标签切换到 Emby 服务器页', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Emby服务器'));
    await tester.pumpAndSettle();

    expect(_shellIndex(tester), 1);
    expect(find.byType(ServerManagerScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('点击标签切换到声网配置页', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('声网配置'));
    await tester.pumpAndSettle();

    expect(_shellIndex(tester), 2);
    expect(find.byType(AgoraConfigScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('点击标签切换到设置页', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(_shellIndex(tester), 3);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('详情页为顶层路由，覆盖底部导航', (tester) async {
    final router = await _pumpApp(tester);

    router.push('/detail/1');
    await tester.pumpAndSettle();

    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.byType(ShellNavBar), findsNothing);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(ShellNavBar), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('扫码页为顶层路由，覆盖底部导航', (tester) async {
    final router = await _pumpApp(tester);

    // 权限流程在测试环境挂起（页面停在加载态），不能 pumpAndSettle，
    // 用固定步长推进转场动画
    router.push('/scan');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QrScannerScreen), findsOneWidget);
    expect(find.byType(ShellNavBar), findsNothing);

    router.pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(QrScannerScreen), findsNothing);
    expect(find.byType(ShellNavBar), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('底部导航胶囊上移，无安全区时留 20 间距', (tester) async {
    await _pumpApp(tester);

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    final insets = padding.padding as EdgeInsets;
    expect(insets.left, 12);
    expect(insets.right, 12);
    expect(insets.bottom, 20, reason: 'v1.1.84 胶囊再上移（原 4）');
  });

  testWidgets('三键虚拟按键(48)时胶囊贴其上沿 +12，避免被遮挡', (tester) async {
    await _pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 48));

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    expect((padding.padding as EdgeInsets).bottom, 60,
        reason: 'v1.1.83 上沿留白 +2 → +12');
  });

  testWidgets('手势导航条(34)时胶囊留 20 间距（按无安全区处理）', (tester) async {
    await _pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 34));

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    expect((padding.padding as EdgeInsets).bottom, 20,
        reason: 'v1.1.84 手势条与无安全区统一 20');
  });

  testWidgets('首页滑到底部导航胶囊淡出隐藏，回滚立即显示', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {'s1': _sessionJson()},
    );
    await _pumpApp(tester, auth: auth, emby: _scrollableEmby());

    expect(_navOpacity(tester), 1.0);

    // 滑到最底部 → 淡出隐藏
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(_navOpacity(tester), 0.0);

    // 回滚 → 淡入显示
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(_navOpacity(tester), 1.0);
  });

  testWidgets('非首页标签滚动不隐藏导航（仅首页生效）', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(_shellIndex(tester), 3);

    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(_navOpacity(tester), 1.0);
  });

  testWidgets('长按导航拖动，松手落点切换标签', (tester) async {
    await _pumpApp(tester);

    final navRect = tester.getRect(find.byType(ShellNavBar));
    final gesture = await tester.startGesture(
      Offset(navRect.left + 100, navRect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 拖到第三格中部松手
    await gesture.moveTo(
      Offset(navRect.left + navRect.width * 0.62, navRect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_shellIndex(tester), 2);
    expect(find.byType(AgoraConfigScreen), findsOneWidget);
  });

  testWidgets('顶层路由表包含分类 / 详情 / 播放 / 房间 / 扫码', (tester) async {
    final router = await _pumpApp(tester);

    final paths = <String>[
      '/category/lib1?name=%E7%94%B5%E5%BD%B1&type=movies',
      '/detail/99',
      '/player/99?isHost=true',
      '/room?code=abc&name=tom',
      '/scan',
    ];
    for (final path in paths) {
      expect(
        router.configuration.findMatch(Uri.parse(path)).isNotEmpty,
        isTrue,
        reason: '路由 $path 应可解析',
      );
    }
  });

  testWidgets('点击首页媒体库卡片进入对应分类海报墙', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {'s1': _sessionJson()},
    );
    await _pumpApp(tester, auth: auth, emby: _scrollableEmby());

    // 媒体库栏按服务端顺序展示 4 张卡片
    expect(find.byKey(const ValueKey('libraryCard_lib0')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryCard_lib3')), findsOneWidget);
    expect(find.text('媒体库'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('libraryCard_lib2')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryScreen), findsOneWidget);
    expect(find.byType(ShellNavBar), findsNothing); // 顶层路由覆盖导航
  });

  testWidgets('壳层带主题色三段渐变背景，默认为应用底色同色三段', (tester) async {
    await _pumpApp(tester);

    final shell = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('shellBackground')),
    );
    final gradient =
        (shell.decoration! as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(
      gradient.colors.toSet(),
      {ThemeData.light().scaffoldBackgroundColor},
    );
  });

  testWidgets('主题色写入后壳层渐变为压暗主题色，切标签仍在', (tester) async {
    await _pumpApp(
      tester,
      settings: const AppSettings(themeColor: 0xFF22D3EE),
    );

    LinearGradient shellGradient() {
      final shell = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('shellBackground')),
      );
      return (shell.decoration! as BoxDecoration).gradient! as LinearGradient;
    }

    expect(
      shellGradient().colors.first,
      PosterPalette.darkenForPage(const Color(0xFF22D3EE)),
    );
    expect(shellGradient().colors.toSet().length, 3);

    // 切到设置页，壳层渐变仍存在
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(shellGradient(), isA<LinearGradient>());
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('detail 路由解析 server 参数注入 DetailScreen', (tester) async {
    final router = await _pumpApp(tester);

    router.push('/detail/42?server=srv-b');
    await tester.pumpAndSettle();
    final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
    expect(detail.itemId, '42');
    expect(detail.serverId, 'srv-b');
    router.pop();
    await tester.pumpAndSettle();

    // player 依赖 libmdk FFI 无法在测试环境挂载，仅断言路由可解析
    // （builder 以 queryParameters['server'] 注入 PlayerScreen.serverId）
    expect(
      router.configuration
          .findMatch(Uri.parse('/player/42?server=srv-b'))
          .isNotEmpty,
      isTrue,
    );
  });

  testWidgets('首页聚合搜索：结果带服务器名，点击不切换激活服务器进详情', (tester) async {
    final serverA = _serverConfig('a', name: '服务器甲');
    final serverB = _serverConfig('b', name: '服务器乙');
    final globalSearch = GlobalSearchService(
      serviceFactory: (cfg) => FakeEmbyService(
        searchResults: [
          MediaItem(
            id: '${cfg.id}-1',
            name: '${cfg.serverName}的影片',
            type: 'Movie',
          ),
        ],
      ),
    );
    final router = await _pumpApp(
      tester,
      serverList: [serverA, serverB],
      currentServer: serverA,
      globalSearch: globalSearch,
    );

    // 首页搜索入口（需要已认证的当前服务器）
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320)); // 搜索防抖到期
    await tester.pumpAndSettle();

    // 两台服务器的结果都出现；服务器名在左栏筛选片与卡片角标
    expect(find.text('服务器甲的影片'), findsOneWidget);
    expect(find.text('服务器乙的影片'), findsOneWidget);
    expect(find.text('服务器乙'), findsWidgets, reason: '左栏筛选片 + 卡片角标');
    expect(find.text('全部'), findsOneWidget, reason: '左栏顶部全部筛选片');

    // 点击另一台服务器的结果：携带 server 参数进详情，激活服务器不切换
    await tester.tap(find.text('服务器乙的影片'));
    await tester.pumpAndSettle();

    final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
    expect(detail.serverId, 'b');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DetailScreen)),
    );
    expect(container.read(embyConfigProvider)?.id, 'a',
        reason: 'Q1=B：搜索不切换激活服务器');

    router.pop();
    await tester.pumpAndSettle();
  });
}

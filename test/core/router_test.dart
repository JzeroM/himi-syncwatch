import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';
import 'package:himi_syncwatch/screens/shell/main_shell.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

import '../helpers/test_fakes.dart';

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  FakeEmbyAuthService? auth,
  FakeEmbyService? emby,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        embyAuthServiceProvider
            .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
        embyServiceProvider.overrideWith((ref) => emby ?? FakeEmbyService()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(
            routerConfig: router,
            // 模拟真机系统栏（edge-to-edge 下 padding 已被消费，仅 viewPadding 保留）
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(viewPadding: viewPadding),
              child: child ?? const SizedBox.shrink(),
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

  testWidgets('底部导航胶囊贴近屏幕底，无安全区时仅留 4 间距', (tester) async {
    await _pumpApp(tester);

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    final insets = padding.padding as EdgeInsets;
    expect(insets.left, 12);
    expect(insets.right, 12);
    expect(insets.bottom, 4);
  });

  testWidgets('三键虚拟按键(48)时胶囊贴其上沿 +2，避免被遮挡', (tester) async {
    await _pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 48));

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    expect((padding.padding as EdgeInsets).bottom, 50);
  });

  testWidgets('手势导航条(34)时胶囊贴近屏底留 6 间距', (tester) async {
    await _pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 34));

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    expect((padding.padding as EdgeInsets).bottom, 6);
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

  testWidgets('顶层路由表包含分类 / 详情 / 播放 / 房间', (tester) async {
    final router = await _pumpApp(tester);

    final paths = <String>[
      '/category/lib1?name=%E7%94%B5%E5%BD%B1&type=movies',
      '/detail/99',
      '/player/99?isHost=true',
      '/room?code=abc&name=tom',
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
}

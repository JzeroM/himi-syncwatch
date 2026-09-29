import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';
import 'package:himi_syncwatch/screens/shell/main_shell.dart';

import '../helpers/test_fakes.dart';

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
        embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(routerConfig: router);
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
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
    expect(find.byType(NavigationBar), findsNothing);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('底部导航胶囊贴近安全区，仅留 6 间距', (tester) async {
    await _pumpApp(tester);

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('shellNavBarPadding')),
    );
    final insets = padding.padding as EdgeInsets;
    expect(insets.left, 12);
    expect(insets.right, 12);
    expect(insets.bottom, 6);
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
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
  FakeEmbyService? emby,
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider.overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServiceProvider.overrideWith((ref) => emby ?? FakeEmbyService()),
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

LinearGradient _bgGradient(WidgetTester tester) {
  final container =
      tester.widget<AnimatedContainer>(find.byKey(const Key('homeBackground')));
  final decoration = container.decoration! as BoxDecoration;
  return decoration.gradient! as LinearGradient;
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

    // 房间（合并后）/ 搜索两个按钮同属一个玻璃椭圆
    final search = tester.widgetList(_capsuleOf(Icons.search)).first;
    final room =
        tester.widgetList(_capsuleOf(Icons.meeting_room_outlined)).first;
    expect(identical(search, room), isTrue);
  });

  testWidgets('服务器下拉为锚定标题的玻璃弹出层', (tester) async {
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
    await _pumpScreen(tester, auth: auth);

    expect(find.byType(GlassContainer), findsNWidgets(2));

    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();

    // 弹出层本身也是玻璃容器（标题胶囊 + 操作胶囊 + 下拉层 = 3）
    expect(find.byType(GlassContainer), findsNWidgets(3));
    expect(find.text('备用服务器'), findsOneWidget);

    // 点击遮罩关闭
    await tester.tapAt(const Offset(400, 560));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNWidgets(2));
  });

  testWidgets('房间按钮弹出玻璃卡片，加入房间分流到房间码弹窗', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(tester, auth: auth);

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();

    // 玻璃卡片含创建/加入两行
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(GlassContainer),
      ),
      findsOneWidget,
    );
    expect(find.text('创建房间'), findsOneWidget);
    expect(find.text('加入房间'), findsOneWidget);
    expect(find.text('开一局同步观影'), findsOneWidget);
    expect(find.text('粘贴或扫码加入'), findsOneWidget);

    // 选择加入房间 → 打开房间码弹窗
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();
    expect(find.text('粘贴房间码'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('房间卡片中创建房间，声网未配置时给出提示', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(tester, auth: auth);

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();

    expect(
      find.text('请先在「声网配置」页填写 App ID 和 App Certificate'),
      findsOneWidget,
    );
  });

  testWidgets('无服务器时房间卡片创建行禁用、加入行可用', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();

    final create = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('创建房间'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(create.onTap, isNull);

    final join = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('加入房间'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(join.onTap, isNotNull);
  });

  testWidgets('首页媒体库栏：按服务端排序展示且过滤空库', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb2',
          name: '华语电影',
          collectionType: 'movies',
          posterUrl: '',
        ),
        LibraryFolder(
          id: 'lbEmpty',
          name: '空库',
          collectionType: 'movies',
          posterUrl: '',
        ),
        LibraryFolder(
          id: 'lb1',
          name: '动画电影',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ],
      itemsByParent: {'lbEmpty': <MediaItem>[]},
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    expect(find.text('媒体库'), findsOneWidget);

    // 空库不显示，其余按服务端下发顺序（华语 → 动画）
    expect(find.byKey(const ValueKey('libraryCard_lb2')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryCard_lb1')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryCard_lbEmpty')), findsNothing);

    final first =
        tester.getTopLeft(find.byKey(const ValueKey('libraryCard_lb2')));
    final second =
        tester.getTopLeft(find.byKey(const ValueKey('libraryCard_lb1')));
    expect(first.dx, lessThan(second.dx));

    // 卡片不包玻璃容器，顶部玻璃椭圆计数保持 2
    expect(find.byType(GlassContainer), findsNWidgets(2));
    // 下方媒体库分区与栏同时存在
    expect(find.text('华语电影'), findsWidgets);
    expect(find.text('动画电影'), findsWidgets);
  });

  testWidgets('首页背景为三段渐变容器（默认=应用底色同色三段）', (tester) async {
    final container = await _pumpScreen(tester);

    final bg = find.byKey(const Key('homeBackground'));
    expect(bg, findsOneWidget);
    expect(container.read(settingsProvider).themeColor, isNull);

    final gradient = _bgGradient(tester);
    expect(gradient.colors, hasLength(3));
    expect(
      gradient.colors.toSet(),
      {ThemeData.light().scaffoldBackgroundColor},
    );
  });

  testWidgets('主题色写入后首页背景变为压暗主题色渐变', (tester) async {
    await _pumpScreen(
      tester,
      settings: const AppSettings(themeColor: 0xFF6366F1),
    );

    final gradient = _bgGradient(tester);
    expect(gradient.colors, hasLength(3));
    expect(
      gradient.colors.first,
      PosterPalette.darkenForPage(const Color(0xFF6366F1)),
    );
    expect(gradient.colors.toSet().length, 3);
  });
}

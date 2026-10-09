import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

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
  EmbyService Function(EmbyServerConfig server)? serviceFactory,
  AppSettings settings = const AppSettings(),
  Future<String?> Function()? qrScan,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider
          .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServiceProvider.overrideWith((ref) => emby ?? FakeEmbyService()),
      if (serviceFactory != null)
        embyServiceFactoryProvider.overrideWithValue(serviceFactory),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: HomeScreen(qrScan: qrScan)),
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

/// 手工构造可被 `RoomCode.decode` 解析的合法房间码（不依赖 token 生成）。
String _validRoomCode() => 'HIMI:${base64Url.encode(utf8.encode(jsonEncode({
          'v': 1,
          'appId': 'a' * 32,
          'channel': 'himi_test',
          't': <dynamic>[],
        })))}';

/// 等 SnackBar 的 5 秒自动消失计时器走完，避免挂起 timer。
Future<void> _settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// getLibraries 挂起在 [gate] 上的 Fake：模拟慢服务器（迟到结果竞态用）。
class _GatedFakeService extends FakeEmbyService {
  _GatedFakeService({
    required super.libraries,
    required super.items,
    required this.gate,
  });

  final Future<void> gate;

  @override
  Future<List<LibraryFolder>> getLibraries() async {
    await gate;
    return libraries;
  }
}

/// getItemCounts 永不返回的 Fake：验证首页首屏不被统计计数阻塞。
class _PendingCountsFakeService extends FakeEmbyService {
  _PendingCountsFakeService({
    required super.libraries,
    required super.items,
  });

  @override
  Future<MediaCounts?> getItemCounts() => Completer<MediaCounts?>().future;
}

/// 可变续播列表 Fake：验证 revision 变化后首页重取「继续观看」。
class _MutableResumeFakeService extends FakeEmbyService {
  _MutableResumeFakeService({
    required super.libraries,
    required super.items,
    required this.resume,
  });

  List<MediaItem> resume;
  int resumeCalls = 0;

  @override
  Future<List<MediaItem>> getResumeItems({int limit = 12}) async {
    resumeCalls++;
    return resume;
  }
}

LibraryFolder _lib(String id, String name) => LibraryFolder(
      id: id,
      name: name,
      collectionType: 'movies',
      posterUrl: '',
    );

void main() {
  testWidgets('无服务器时显示引导到 Emby 服务器标签的空态', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('暂无服务器'), findsOneWidget);
    expect(
      find.text('请到「Emby」标签添加 Emby 服务器'),
      findsOneWidget,
    );
  });

  testWidgets('不再使用侧边栏与菜单按钮', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(Drawer), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('TV 模式首页不渲染顶栏（标题/搜索/房间上移壳层顶栏）', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(
      tester,
      auth: auth,
      settings: const AppSettings(tvMode: true),
    );

    // 顶栏职责全部由壳层 TvTopNavBar 承担，首页自身无 AppBar 与入口按钮
    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.byIcon(Icons.meeting_room_outlined), findsNothing);
    expect(find.text('家庭NAS'), findsNothing);
    // 正常加载内容
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('顶栏无通栏玻璃条，仅标题与操作两个玻璃椭圆', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(GlassBackdrop), findsNothing);
    expect(find.byType(GlassContainer), findsNWidgets(2));
    expect(find.text('HIMI'), findsOneWidget);
    // 空态标题同样被玻璃椭圆包裹
    expect(_capsuleOf(Icons.dns_outlined), findsOneWidget);
    // 顶栏两个椭圆都不绘制黑色悬浮投影
    for (final capsule
        in tester.widgetList<GlassContainer>(find.byType(GlassContainer))) {
      expect(capsule.showShadow, isFalse);
    }
  });

  testWidgets('已有服务器时顶栏两个玻璃椭圆同样无悬浮投影', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(tester, auth: auth);

    final capsules = tester.widgetList<GlassContainer>(
      find.byType(GlassContainer),
    );
    expect(capsules.length, 2);
    for (final capsule in capsules) {
      expect(capsule.showShadow, isFalse);
    }
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

  testWidgets('计数挂起时分类已渲染（首屏不被统计阻塞）', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = _PendingCountsFakeService(
      libraries: [_lib('lib1', '电影库')],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    // 分类已出：内容不被 getItemCounts 阻塞
    expect(find.text('电影库'), findsWidgets);
    // 计数仍挂起 → 统计面板尚未渲染
    expect(find.byKey(const ValueKey('statsPanel')), findsNothing);
  });

  testWidgets('有续播条目时渲染「继续观看」栏，无则不渲染', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: [_lib('lib1', '电影库')],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
      resumeItems: [
        MediaItem(
          id: 'r1',
          name: '续播电影',
          type: 'Movie',
          year: '2026',
          playbackPositionMs: 169000,
          playedPercentage: 20,
        ),
      ],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    expect(find.text('继续观看'), findsOneWidget);
    expect(find.byKey(const ValueKey('continueCard_r1')), findsOneWidget);
  });

  testWidgets('无续播条目时不渲染「继续观看」栏', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: [_lib('lib1', '电影库')],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    expect(find.text('继续观看'), findsNothing);
  });

  testWidgets('续播修订号变化后「继续观看」栏即时重取', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = _MutableResumeFakeService(
      libraries: [_lib('lib1', '电影库')],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
      resume: [
        MediaItem(
          id: 'r1',
          name: '续播电影',
          type: 'Movie',
          playbackPositionMs: 1000,
          playedPercentage: 20,
        ),
      ],
    );
    final container = await _pumpScreen(tester, auth: auth, emby: emby);
    expect(find.byKey(const ValueKey('continueCard_r1')), findsOneWidget);

    // 模拟播放停止上报：服务器续播清空 + bump revision
    emby.resume = [];
    container.read(resumeRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('continueCard_r1')), findsNothing);
    expect(find.text('继续观看'), findsNothing);
    expect(emby.resumeCalls, greaterThanOrEqualTo(2), reason: 'revision 变化应重取');
  });

  testWidgets('乐观隐藏集合中的续播条目立即从栏中移除', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = _MutableResumeFakeService(
      libraries: [_lib('lib1', '电影库')],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
      resume: [
        MediaItem(
          id: 'r1',
          name: '续播电影',
          type: 'Movie',
          playbackPositionMs: 1000,
          playedPercentage: 20,
        ),
      ],
    );
    final container = await _pumpScreen(tester, auth: auth, emby: emby);
    expect(find.byKey(const ValueKey('continueCard_r1')), findsOneWidget);

    // 点「重播」→ 乐观隐藏该条 → 首页立即移除（无需等上报/刷新）
    container.read(resumeOptimisticHiddenProvider.notifier).state = {'r1'};
    await tester.pump();

    expect(find.byKey(const ValueKey('continueCard_r1')), findsNothing);
    expect(find.text('继续观看'), findsNothing);
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

  testWidgets('切换服务器后首页内容跟随切换到新服务器数据', (tester) async {
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
    final fakeA = FakeEmbyService(
      libraries: [_lib('lbA', 'A库')],
      items: [MediaItem(id: 'ma', name: '影片A', type: 'Movie')],
    );
    final fakeB = FakeEmbyService(
      libraries: [_lib('lbB', 'B库')],
      items: [MediaItem(id: 'mb', name: '影片B', type: 'Movie')],
    );
    final container = await _pumpScreen(
      tester,
      auth: auth,
      emby: fakeA,
      serviceFactory: (server) => server.id == 'srv_b' ? fakeB : fakeA,
    );

    expect(find.text('A库'), findsWidgets);
    expect(find.text('B库'), findsNothing);

    // 顶栏下拉切到备用服务器
    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_b');
    // 内容必须跟随切换（竞态修复守护：不能仍是旧服务器数据）
    expect(find.text('B库'), findsWidgets);
    expect(find.text('A库'), findsNothing);
  });

  testWidgets('快速切换时迟到的旧服务器结果不覆盖新内容', (tester) async {
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
    final fakeA = FakeEmbyService(
      libraries: [_lib('lbA', 'A库')],
      items: [MediaItem(id: 'ma', name: '影片A', type: 'Movie')],
    );
    final gateB = Completer<void>();
    final fakeB = _GatedFakeService(
      libraries: [_lib('lbB', 'B库')],
      items: [MediaItem(id: 'mb', name: '影片B', type: 'Movie')],
      gate: gateB.future,
    );
    final container = await _pumpScreen(
      tester,
      auth: auth,
      emby: fakeA,
      serviceFactory: (server) => server.id == 'srv_b' ? fakeB : fakeA,
    );

    expect(find.text('A库'), findsWidgets);

    // 切到 B（慢服务器，请求挂起，spinner 转动中不能 pumpAndSettle）
    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用服务器'));
    // 下拉关闭动画需两帧推进走完（spinner 转动中不能 pumpAndSettle）
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    // 趁 B 加载中切回 A（A 立即返回）
    await tester.tap(find.text('备用服务器'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_a');
    expect(find.text('A库'), findsWidgets);

    // B 的迟到结果此刻返回，必须被丢弃
    gateB.complete();
    await tester.pumpAndSettle();

    expect(find.text('A库'), findsWidgets);
    expect(find.text('B库'), findsNothing);
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

  testWidgets('扫码返回后房间码写回输入框，昵称为空时留在弹窗提示', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final code = _validRoomCode();
    await _pumpScreen(tester, auth: auth, qrScan: () async => code);

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();
    expect(find.text('粘贴房间码'), findsOneWidget);

    await tester.tap(find.text('扫码加入'));
    await tester.pumpAndSettle();

    // 扫码码写回输入框，弹窗保持打开并提示补昵称（不再丢失房间码）
    final codeField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(codeField.controller!.text, code);
    expect(find.text('粘贴房间码'), findsOneWidget);
    expect(find.text('已扫描到房间码，请填写昵称后加入'), findsOneWidget);
    await _settleSnackbars(tester);
  });

  testWidgets('码与昵称齐全时点加入关闭弹窗并发起进房路由', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    await _pumpScreen(tester, auth: auth);

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), _validRoomCode());
    await tester.enterText(find.byType(TextField).at(1), '小明');
    await tester.tap(find.text('加入'));
    await tester.pump();

    // 成功分支先关弹窗再 push /player/_（测试环境无 GoRouter/无法挂载
    // PlayerScreen，此处以 takeException 证明进房调用已发生）
    final exception = tester.takeException();
    expect(exception, isNotNull);
    expect(exception.toString(), contains('GoRouter'));
    await tester.pumpAndSettle();
    expect(find.text('粘贴房间码'), findsNothing);
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

    // 标题移到封面下方，不再用黑渐变盖在封面上
    final card = find.byKey(const ValueKey('libraryCard_lb2'));
    final cover = tester.getRect(
      find.descendant(of: card, matching: find.byType(EmbyImage)),
    );
    final title = tester.getRect(
      find.descendant(of: card, matching: find.text('华语电影')),
    );
    expect(title.top, greaterThanOrEqualTo(cover.bottom));

    // 卡片不包玻璃容器，顶部玻璃椭圆计数保持 2
    expect(find.byType(GlassContainer), findsNWidgets(2));
    // 下方媒体库分区与栏同时存在
    expect(find.text('华语电影'), findsWidgets);
    expect(find.text('动画电影'), findsWidgets);
  });

  testWidgets('TV 焦点框不被裁：首页横条列表全部 Clip.none', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb1',
          name: '动画电影',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ],
      items: [
        MediaItem(id: 'm1', name: '影片1', type: 'Movie'),
      ],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    final horizontals = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((w) => w.scrollDirection == Axis.horizontal)
        .toList();
    expect(horizontals, isNotEmpty, reason: '首页存在横条列表');
    for (final lv in horizontals) {
      expect(lv.clipBehavior, Clip.none,
          reason: 'TV 焦点框 1.06 放大溢出内容盒，clip 会裁掉上下边');
    }
  });

  testWidgets('分类标题行焦点环只包标题文字（不撑满整行）', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb1',
          name: '动画电影',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ],
      items: [MediaItem(id: 'm1', name: '影片1', type: 'Movie')],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    // 分类标题行 = TvFocusable → Row(标题 + chevron)
    final header = find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(TvFocusable),
    );
    expect(header, findsOneWidget);

    // 焦点环只包住「动画电影 ›」：宽度远小于屏宽（修复前 Row 撑满整行）
    final w = tester.getSize(header).width;
    expect(w, lessThan(tester.view.physicalSize.width * 0.5));
    // 标题确实在焦点块内
    expect(
      find.descendant(of: header, matching: find.text('动画电影')),
      findsOneWidget,
    );
  });

  testWidgets('首页分类行：最近添加按 DateLastContentAdded（有新集的剧排前）', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb1',
          name: '国产剧',
          collectionType: 'tvshows',
          posterUrl: '',
        ),
      ],
      items: [
        MediaItem(
          id: 'sv1',
          name: '更新了的剧',
          type: 'Series',
          posterUrl: '',
        ),
      ],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    expect(
      emby.lastGetItemsSortBy,
      'DateLastContentAdded',
      reason: 'DateCreated 是系列首次入库时间、有新集也不变——更新过的'
          '剧集排不到最前；DateLastContentAdded 随子集入库更新',
    );
    expect(emby.lastGetItemsSortOrder, 'Descending');
    expect(find.byKey(const ValueKey('posterCard_sv1')), findsOneWidget);
  });

  testWidgets('首页分类卡片：海报完整 2:3、标题在海报下方、带评分与集数角标', (tester) async {
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
      ],
      items: [
        MediaItem(
          id: 'm1',
          name: '测试影片',
          type: 'Movie',
          posterUrl: '',
          year: '2026',
          communityRating: 8.5,
          indexNumber: 12,
        ),
      ],
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    // 不再套黑底 Card
    expect(find.byType(Card), findsNothing);

    final card = find.byKey(const ValueKey('posterCard_m1'));
    expect(card, findsOneWidget);

    final poster = tester.getRect(
      find.descendant(of: card, matching: find.byType(EmbyImage)),
    );
    final title = tester.getRect(
      find.descendant(of: card, matching: find.text('测试影片')),
    );
    final year = tester.getRect(
      find.descendant(of: card, matching: find.text('2026')),
    );

    // 海报完整 2:3，标题与年份依次排在海报下方
    expect(poster.height, closeTo(poster.width * 1.5, 0.5));
    expect(title.top, greaterThanOrEqualTo(poster.bottom));
    expect(year.top, greaterThanOrEqualTo(title.bottom));

    // 评分在海报右下、集数在左上
    expect(
      find.descendant(of: card, matching: find.text('8.5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('12')),
      findsOneWidget,
    );
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

  testWidgets('底部统计面板：计数成功时渲染在分类行之后', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb1',
          name: '影库',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ],
      items: [
        MediaItem(id: 'm1', name: '测试影片', type: 'Movie', posterUrl: ''),
      ],
      itemCounts: const MediaCounts(
        movies: 2565,
        series: 2415,
        episodes: 73462,
      ),
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    final panel = find.byKey(const ValueKey('statsPanel'));
    expect(panel, findsOneWidget);
    expect(find.text('2565'), findsOneWidget);
    expect(find.text('2415'), findsOneWidget);
    expect(find.text('73462'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('集'), findsOneWidget);

    // 面板排在分类海报卡之后（列表收尾）
    final poster = find.byKey(const ValueKey('posterCard_m1'));
    expect(
      tester.getTopLeft(panel).dy,
      greaterThanOrEqualTo(tester.getBottomRight(poster).dy),
    );
  });

  testWidgets('统计失败（getItemCounts 返 null）时隐藏底部面板', (tester) async {
    final auth = FakeEmbyAuthService(
      serverIds: ['s1'],
      sessions: {
        's1': _sessionJson(id: 'srv_a', serverId: 's1', serverUrl: 'https://a'),
      },
    );
    final emby = FakeEmbyService(
      libraries: const [
        LibraryFolder(
          id: 'lb1',
          name: '影库',
          collectionType: 'movies',
          posterUrl: '',
        ),
      ],
      items: [
        MediaItem(id: 'm1', name: '测试影片', type: 'Movie', posterUrl: ''),
      ],
      itemCounts: null,
    );
    await _pumpScreen(tester, auth: auth, emby: emby);

    expect(find.byKey(const ValueKey('statsPanel')), findsNothing);
    expect(find.text('电影'), findsNothing);
    // 内容不受统计失败影响
    expect(find.byKey(const ValueKey('posterCard_m1')), findsOneWidget);
  });
}

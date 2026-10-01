import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/widgets/tv/tv_directional_scroll.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

/// 顶栏 ↔ 内容区焦点往返（真机反馈：从顶栏下移后按上键回不到顶栏）。
///
/// 结构对齐 main_shell TV 分支：Column[顶栏, Expanded(列表)]，
/// 顶层挂 TvRemoteShortcuts（方向键滚动贯通挂载层）。

const _topTitle = ValueKey('topTitle');
const _topSearch = ValueKey('topSearch');

Widget _page({bool withHorizontalRow = false}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
    ],
    child: TvRemoteShortcuts(
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    TvFocusable(
                      key: _topTitle,
                      autofocus: true,
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('标题'),
                      ),
                    ),
                    TvFocusable(
                      key: _topSearch,
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.search),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: 50,
                  itemBuilder: (context, i) => SizedBox(
                    key: ValueKey('item_$i'),
                    height: 60,
                    child: withHorizontalRow && i == 0
                        ? SizedBox(
                            height: 60,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: 20,
                              itemBuilder: (context, j) => SizedBox(
                                key: ValueKey('hitem_$j'),
                                width: 120,
                                child: TvFocusable(
                                  onTap: () {},
                                  child: Center(child: Text('hitem $j')),
                                ),
                              ),
                            ),
                          )
                        : TvFocusable(
                            onTap: () {},
                            child: Center(child: Text('item $i')),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 焦点是否位于 [key] 组件子树内。
bool _focusWithin(WidgetTester tester, Key key) {
  final node = FocusManager.instance.primaryFocus?.context;
  if (node is! Element) return false;
  final target = find.byKey(key).evaluate().firstOrNull;
  if (target == null) return false;
  if (identical(node, target)) return true;
  var found = false;
  // ignore: avoid_types_on_closure_parameters
  node.visitAncestorElements((Element a) {
    if (a == target) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 焦点是否落在某个 item_N（竖列表）。
int? _focusedItemIndex(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus?.context;
  if (node is! Element) return null;
  for (var i = 0; i < 50; i++) {
    final target = find.byKey(ValueKey('item_$i')).evaluate().firstOrNull;
    if (target == null) continue;
    var found = false;
    // ignore: avoid_types_on_closure_parameters
    node.visitAncestorElements((Element a) {
      if (a == target) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return i;
  }
  return null;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Map<String, dynamic> _sessionJson() => {
      'id': 'srv_a',
      'serverId': 's1',
      'serverUrl': 'https://a',
      'serverName': '家庭NAS',
      'userId': 'uid',
      'username': 'user',
      'accessToken': 'token',
    };

/// 真实结构（main_shell TV 分支 + 首页数据，960×540 盒子视口）。
Future<void> _pumpRealApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
      for (var i = 0; i < 12; i++)
        MediaItem(id: 'm$i', name: '影片$i', type: 'Movie'),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
        embyAuthServiceProvider.overrideWith(
          (ref) => FakeEmbyAuthService(
            serverIds: ['s1'],
            sessions: {'s1': _sessionJson()},
          ),
        ),
        embyServiceProvider.overrideWith((ref) => emby),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);
          // 与 HimiSyncApp 相同挂载层：MaterialApp.builder 内、Navigator 外
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                TvRemoteShortcuts(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 焦点是否落在壳层顶部导航内。
bool _focusInTopBar() {
  final node = FocusManager.instance.primaryFocus?.context;
  if (node is! Element) return false;
  final top = find.byType(TvTopNavBar).evaluate().firstOrNull;
  if (top == null) return false;
  var found = false;
  // ignore: avoid_types_on_closure_parameters
  node.visitAncestorElements((Element a) {
    if (a == top) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  testWidgets('焦点在顶栏按上键不越界，按下键进入内容', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    // 初始：autofocus 落在顶栏标题
    expect(_focusWithin(tester, _topTitle), isTrue);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedItemIndex(tester), isNotNull, reason: '按下键应从顶栏进入列表内容');
  });

  testWidgets('复现：顶栏下移进内容后，按上键回到顶栏', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.arrowDown);
    final inContent = _focusedItemIndex(tester);
    expect(inContent, isNotNull, reason: '焦点应先进入内容');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    final backToTop =
        _focusWithin(tester, _topTitle) || _focusWithin(tester, _topSearch);
    expect(backToTop, isTrue, reason: '按上键后焦点应回到顶栏（当前焦点在 item=$inContent）');
  });

  testWidgets('复现：列表滚动到中部后连按上键回到顶栏', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    // 连按下键把列表滚起来（焦点深入中部）
    for (var i = 0; i < 25; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    final mid = _focusedItemIndex(tester);
    expect(mid, isNotNull);

    // 连按上键：应逐级/贯通回顶栏
    for (var i = 0; i < 40; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      if (_focusWithin(tester, _topTitle) || _focusWithin(tester, _topSearch)) {
        break;
      }
    }
    final backToTop =
        _focusWithin(tester, _topTitle) || _focusWithin(tester, _topSearch);
    expect(backToTop, isTrue, reason: '从 item=$mid 连按上键应回到顶栏');
  });

  testWidgets('复现：横滑区焦点按上键能穿出回到顶栏', (tester) async {
    await tester.pumpWidget(_page(withHorizontalRow: true));
    await tester.pump();

    // 下移进内容：第一个 item 是横滑行，焦点落进横滑卡片
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // 再确保焦点在横滑卡片上（若落在 item 容器则继续下移一次）
    final node = FocusManager.instance.primaryFocus?.context;
    final inH = node is Element &&
        find.byKey(const ValueKey('hitem_0')).evaluate().isNotEmpty;
    if (!inH) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }

    // 连按上键：应穿出横滑区、穿过竖列表回顶栏
    for (var i = 0; i < 40; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      if (_focusWithin(tester, _topTitle) || _focusWithin(tester, _topSearch)) {
        break;
      }
    }
    final backToTop =
        _focusWithin(tester, _topTitle) || _focusWithin(tester, _topSearch);
    expect(backToTop, isTrue, reason: '从横滑区按上键应回到顶栏');
  });

  testWidgets('真实结构：main_shell TV 首页焦点下移后连按上键回顶栏', (tester) async {
    await _pumpRealApp(tester);
    expect(find.byType(TvTopNavBar), findsOneWidget);

    // 冷启动无焦点：OK 落焦进作用域（应落顶栏第一项）
    await _press(tester, LogicalKeyboardKey.enter);
    expect(_focusInTopBar(), isTrue, reason: 'OK 落焦应进入顶栏');

    // 下移进内容
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusInTopBar(), isFalse, reason: '下移后焦点应离开顶栏进入内容');

    // 连按上键：应回到顶栏
    for (var i = 0; i < 40; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      if (_focusInTopBar()) break;
    }
    expect(_focusInTopBar(), isTrue,
        reason: '从内容按上键应回到顶栏（当前 primaryFocus='
            '${FocusManager.instance.primaryFocus?.debugLabel}）');
  });
}

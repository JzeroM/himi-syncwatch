import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/media_state_override_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/media_context_menu.dart';

import '../helpers/test_fakes.dart';

MediaItem _item({bool favorite = false, bool watched = false}) => MediaItem(
      id: 'm1',
      name: '测试影片',
      type: 'Movie',
      isFavorite: favorite,
      isWatched: watched,
    );

EmbyServerConfig _serverConfig(String id) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.local',
      serverName: '服务器$id',
      serverId: '$id-sid',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

Widget _host(
  FakeEmbyService fake, {
  required MediaItem item,
  required bool resume,
  FakeEmbyService? sourceFake,
  String? serverId,
  Rect anchor = const Rect.fromLTWH(40, 300, 100, 150),
  List<Override> extraOverrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServiceProvider.overrideWith((ref) => fake),
      embyServiceForProvider.overrideWith(
        (ref, id) => id == null ? fake : (sourceFake ?? fake),
      ),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => resume
                  ? showResumeCardMenu(
                      context,
                      ref,
                      item,
                      anchor,
                      serverId: serverId,
                    )
                  : showPosterCardMenu(context, ref, item, anchor,
                      serverId: serverId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('海报卡菜单：按状态只显示一条', () {
    testWidgets('已收藏+已观看 → 取消收藏 / 取消已观看', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(favorite: true, watched: true),
        resume: false,
      ));
      await _open(tester);

      expect(find.text('取消收藏'), findsOneWidget);
      expect(find.text('取消已观看'), findsOneWidget);
      expect(find.text('收藏'), findsNothing);
      expect(find.text('标记已观看'), findsNothing);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('未收藏+未观看 → 收藏 / 标记已观看', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(),
        resume: false,
      ));
      await _open(tester);

      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('标记已观看'), findsOneWidget);
      expect(find.text('取消收藏'), findsNothing);
      expect(find.text('取消已观看'), findsNothing);
    });
  });

  group('继续观看菜单：收藏/取消收藏 + 移除历史（无已观看项）', () {
    testWidgets('已收藏 → 取消收藏 + 移除历史', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(favorite: true),
        resume: true,
      ));
      await _open(tester);

      expect(find.text('取消收藏'), findsOneWidget);
      expect(find.text('移除历史'), findsOneWidget);
      expect(find.text('标记已观看'), findsNothing);
      expect(find.text('取消已观看'), findsNothing);
      expect(find.text('收藏'), findsNothing);
    });

    testWidgets('未收藏 → 收藏 + 移除历史', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(),
        resume: true,
      ));
      await _open(tester);

      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('移除历史'), findsOneWidget);
      expect(find.text('标记已观看'), findsNothing);
      expect(find.text('取消已观看'), findsNothing);
    });
  });

  group('跨服务器动作按来源服务器调用', () {
    testWidgets('收藏与移除历史都打到来源服务器', (tester) async {
      final current = FakeEmbyService();
      final source = FakeEmbyService();
      await tester.pumpWidget(_host(
        current,
        item: _item(),
        resume: true,
        sourceFake: source,
        serverId: 's2',
      ));

      await _open(tester);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      expect(current.favoriteCalls, isEmpty);
      expect(source.favoriteCalls.single.id, 'm1');
      expect(source.favoriteCalls.single.favorite, isTrue);

      await _open(tester);
      await tester.tap(find.text('移除历史'));
      await tester.pumpAndSettle();

      expect(current.removedResumeCalls, isEmpty);
      expect(source.removedResumeCalls, ['m1']);
    });

    testWidgets('海报卡标记已观看打到来源服务器', (tester) async {
      final current = FakeEmbyService();
      final source = FakeEmbyService();
      await tester.pumpWidget(_host(
        current,
        item: _item(),
        resume: false,
        sourceFake: source,
        serverId: 's2',
      ));

      await _open(tester);
      await tester.tap(find.text('标记已观看'));
      await tester.pumpAndSettle();

      expect(current.watchedCalls, isEmpty);
      expect(source.watchedCalls.single.id, 'm1');
      expect(source.watchedCalls.single.watched, isTrue);
    });

    testWidgets('移除历史联动所有在线服务器的同一条目', (tester) async {
      final serverA = _serverConfig('a');
      final serverB = _serverConfig('b');
      final fakeA = FakeEmbyService();
      final fakeB = FakeEmbyService(
        resumeItems: [
          MediaItem(
            id: 'b-m1',
            name: '测试影片',
            type: 'Movie',
            providerIds: const {'Tmdb': '1'},
          ),
        ],
      );
      final list = EmbyServerListNotifier()..setList([serverA, serverB]);
      final config = EmbyConfigNotifier()..setConfig(serverA);
      final item = MediaItem(
        id: 'a-m1',
        name: '测试影片',
        type: 'Movie',
        providerIds: const {'Tmdb': '1'},
      );
      await tester.pumpWidget(_host(
        fakeA,
        item: item,
        resume: true,
        serverId: 'a',
        extraOverrides: [
          embyConfigProvider.overrideWith((ref) => config),
          embyServerListProvider.overrideWith((ref) => list),
          embyServiceFactoryProvider.overrideWithValue(
            (server) => server.id == 'b' ? fakeB : fakeA,
          ),
        ],
      ));

      await _open(tester);
      await tester.tap(find.text('移除历史'));
      await tester.pumpAndSettle();

      expect(fakeA.removedResumeCalls, ['a-m1']);
      expect(fakeB.removedResumeCalls, ['b-m1']);
    });
  });

  group('动作调用 Emby', () {
    testWidgets('点「收藏」调 setFavorite(true)', (tester) async {
      final fake = FakeEmbyService();
      await tester.pumpWidget(_host(fake, item: _item(), resume: false));
      await _open(tester);

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      expect(fake.favoriteCalls.single.id, 'm1');
      expect(fake.favoriteCalls.single.favorite, isTrue);
    });

    testWidgets('点「取消收藏」调 setFavorite(false)', (tester) async {
      final fake = FakeEmbyService();
      await tester
          .pumpWidget(_host(fake, item: _item(favorite: true), resume: false));
      await _open(tester);

      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();

      expect(fake.favoriteCalls.single.favorite, isFalse);
    });

    testWidgets('点「标记已观看」调 setWatched(true)', (tester) async {
      final fake = FakeEmbyService();
      await tester.pumpWidget(_host(fake, item: _item(), resume: false));
      await _open(tester);

      await tester.tap(find.text('标记已观看'));
      await tester.pumpAndSettle();

      expect(fake.watchedCalls.single.id, 'm1');
      expect(fake.watchedCalls.single.watched, isTrue);
    });

    testWidgets('失败 → 回滚无（仅提示），不抛错', (tester) async {
      final fake = FakeEmbyService()..favoriteSetResult = false;
      await tester.pumpWidget(_host(fake, item: _item(), resume: false));
      await _open(tester);

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      expect(fake.favoriteCalls.single.favorite, isTrue);
      expect(find.text('操作失败，请检查网络'), findsOneWidget);
    });
  });

  group('面板尺寸与内容', () {
    testWidgets('宽度等于卡片宽（>=140）', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(),
        resume: false,
        anchor: const Rect.fromLTWH(40, 300, 200, 150),
      ));
      await _open(tester);
      expect(tester.getSize(find.byType(GlassContainer)).width, 200);
    });

    testWidgets('窄卡片宽度夹到下限 140', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(),
        resume: false,
        anchor: const Rect.fromLTWH(40, 300, 90, 150),
      ));
      await _open(tester);
      expect(tester.getSize(find.byType(GlassContainer)).width, 140);
    });

    testWidgets('内容左对齐（原方案）', (tester) async {
      await tester.pumpWidget(_host(
        FakeEmbyService(),
        item: _item(),
        resume: false,
        anchor: const Rect.fromLTWH(40, 300, 200, 150),
      ));
      await _open(tester);

      final menu = tester.getRect(find.byType(GlassContainer));
      final icon = tester.getRect(find.byIcon(Icons.favorite_border));
      expect(icon.left, closeTo(menu.left + 16, 0.5));
    });
  });

  group('再次长按回显最新状态（乐观覆盖）', () {
    testWidgets('点收藏 → 再开菜单显示取消收藏', (tester) async {
      final fake = FakeEmbyService();
      await tester.pumpWidget(_host(fake, item: _item(), resume: false));

      await _open(tester);
      expect(find.text('收藏'), findsOneWidget);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(fake.favoriteCalls.single.favorite, isTrue);

      // 再次长按打开：条目快照仍是未收藏，但覆盖让它显示「取消收藏」
      await _open(tester);
      expect(find.text('取消收藏'), findsOneWidget);
      expect(find.text('收藏'), findsNothing);
    });

    testWidgets('点标记已观看 → 再开菜单显示取消已观看', (tester) async {
      final fake = FakeEmbyService();
      await tester.pumpWidget(_host(fake, item: _item(), resume: false));

      await _open(tester);
      await tester.tap(find.text('标记已观看'));
      await tester.pumpAndSettle();

      await _open(tester);
      expect(find.text('取消已观看'), findsOneWidget);
      expect(find.text('标记已观看'), findsNothing);
    });
  });

  group('MediaStateOverrideNotifier', () {
    test('收藏/已观看分别写入并保留彼此', () {
      final n = MediaStateOverrideNotifier();
      n.setFavorite('a', true);
      expect(n.state['a']?.favorite, isTrue);
      expect(n.state['a']?.watched, isNull);

      n.setWatched('a', true);
      expect(n.state['a']?.favorite, isTrue);
      expect(n.state['a']?.watched, isTrue);

      n.setFavorite('a', false);
      expect(n.state['a']?.favorite, isFalse);
      expect(n.state['a']?.watched, isTrue, reason: '改收藏不动已观看');
    });
  });
}

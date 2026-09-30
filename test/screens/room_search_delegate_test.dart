import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/screens/player/room_search_delegate.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _config(String id, {String? name}) {
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

Future<void> _pumpSearch(
  WidgetTester tester, {
  required void Function(Map<String, dynamic>?) onResult,
}) async {
  final serverA = _config('a', name: '服务器甲');
  final serverB = _config('b', name: '服务器乙');
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList([serverA, serverB]),
        ),
        globalSearchProvider.overrideWithValue(globalSearch),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return Scaffold(
              body: ElevatedButton(
                key: const ValueKey('openSearch'),
                onPressed: () async {
                  final result = await showSearch<Map<String, dynamic>?>(
                    context: context,
                    delegate: RoomSearchDelegate(ref, roomCode: 'rc'),
                  );
                  onResult(result);
                },
                child: const Text('搜索'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('房间搜索聚合全部服务器，副标题显示服务器名', (tester) async {
    await _pumpSearch(tester, onResult: (_) {});

    await tester.tap(find.byKey(const ValueKey('openSearch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pumpAndSettle();

    expect(find.text('服务器甲的影片'), findsOneWidget);
    expect(find.text('服务器乙的影片'), findsOneWidget);
    expect(find.text('服务器甲'), findsOneWidget);
    expect(find.text('服务器乙'), findsOneWidget);
  });

  testWidgets('选中结果返回 itemId 与来源服务器 serverId', (tester) async {
    Map<String, dynamic>? result;
    await _pumpSearch(tester, onResult: (r) => result = r);

    await tester.tap(find.byKey(const ValueKey('openSearch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pumpAndSettle();

    await tester.tap(find.text('服务器乙的影片'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!['itemId'], 'b-1');
    expect(result!['serverId'], 'b');
    expect(result!['name'], '服务器乙的影片');
  });
}

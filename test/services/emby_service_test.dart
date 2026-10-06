import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 启动一个本地 HTTP 服务，捕获 EmbyService 发出的请求路径与查询参数。
class _CapturedRequest {
  final String method;
  final String path;
  final Map<String, List<String>> query;
  final Map<String, dynamic> body;

  _CapturedRequest(this.method, this.path, this.query, this.body);

  String? param(String key) => query[key]?.first;
}

void main() {
  late HttpServer server;
  late List<_CapturedRequest> captured;
  late EmbyService service;

  /// 可按测试用例替换的响应体生成器（默认空 Items）。
  late Map<String, dynamic> Function(String path) respondWith;

  setUp(() async {
    captured = <_CapturedRequest>[];
    respondWith = (_) => {'Items': <dynamic>[]};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    unawaited(() async {
      await for (final request in server) {
        final rawBody = await utf8.decoder.bind(request).join();
        final body = rawBody.isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(rawBody) as Map).cast<String, dynamic>();
        captured.add(
          _CapturedRequest(
            request.method,
            request.uri.path,
            request.uri.queryParametersAll,
            body,
          ),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(respondWith(request.uri.path)));
        await request.response.close();
      }
    }());

    service = EmbyService();
    service.configure(
      serverUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'test-token',
      userId: 'user-1',
      serverId: 'server-1',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('getItems 排序参数透传', () {
    test('sortBy=DateCreated & sortOrder=Descending 进入查询串', () async {
      await service.getItems(
        parentId: 'lib-1',
        limit: 20,
        includeItemTypes: 'Movie,Series',
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );

      expect(captured, hasLength(1));
      final req = captured.single;
      expect(req.path, '/Items');
      expect(req.param('SortBy'), 'DateCreated');
      expect(req.param('SortOrder'), 'Descending');
      expect(req.param('ParentId'), 'lib-1');
      expect(req.param('Limit'), '20');
      expect(req.param('IncludeItemTypes'), 'Movie,Series');
    });

    test('未传排序参数时不注入 SortBy / SortOrder', () async {
      await service.getItems(parentId: 'lib-1', limit: 20);

      final req = captured.single;
      expect(req.param('SortBy'), isNull);
      expect(req.param('SortOrder'), isNull);
    });

    test('分类页其他排序方式同样可透传', () async {
      await service.getItems(
        parentId: 'lib-1',
        sortBy: 'SortName',
        sortOrder: 'Ascending',
      );

      final req = captured.single;
      expect(req.param('SortBy'), 'SortName');
      expect(req.param('SortOrder'), 'Ascending');
    });
  });

  group('getItems 其他行为保持不变', () {
    test('Recursive 固定为 true，ImageTypeLimit 固定为 1', () async {
      await service.getItems(parentId: 'lib-1');

      final req = captured.single;
      expect(req.param('Recursive'), 'true');
      expect(req.param('ImageTypeLimit'), '1');
      expect(req.param('UserId'), 'user-1');
    });

    test('空 Items 响应返回空列表', () async {
      final items = await service.getItems(parentId: 'lib-1');
      expect(items, isEmpty);
    });
  });

  group('AlternateMediaSources（Emby 4.9.x 非管理员多版本）', () {
    // Emby 4.9.x 起批量端点对非管理员每条只回 1 个 MediaSource，
    // 需显式请求该字段才返回全部版本（官方 Luke 给出的 workaround）。
    test('getItems 默认 Fields 含 AlternateMediaSources', () async {
      await service.getItems(parentId: 'series-1', includeItemTypes: 'Episode');

      final fields = captured.single.param('Fields')!;
      expect(fields, contains('MediaSources'));
      expect(fields, contains('AlternateMediaSources'));
    });

    test('getItemDetails Fields 含 AlternateMediaSources', () async {
      respondWith = (_) => {'Id': 'ep-1', 'Type': 'Episode', 'Name': 'E1'};

      await service.getItemDetails('ep-1');

      final req = captured.single;
      expect(req.path, '/Users/user-1/Items/ep-1');
      final fields = req.param('Fields')!;
      expect(fields, contains('MediaSources'));
      expect(fields, contains('AlternateMediaSources'));
    });
  });

  group('getLibraries 保持服务端媒体库排序', () {
    test('请求带 Fields=ImageTags、不注入 SortBy，顺序与服务端一致', () async {
      respondWith = (_) => {
            'Items': [
              {
                'Name': '动画电影',
                'ItemId': 'L2',
                'CollectionType': 'movies',
                'ImageTags': {'Primary': 'tag-2'},
              },
              {
                'Name': '华语电影',
                'Id': 'L1',
                'CollectionType': 'movies',
                'ImageTags': <String, dynamic>{},
              },
              {
                'Name': '外语电影',
                'ItemId': 'L3',
                'CollectionType': 'movies',
              },
            ],
          };

      final libs = await service.getLibraries();

      final req = captured.single;
      expect(req.path, '/Users/user-1/Views');
      expect(req.param('Fields'), 'ImageTags');
      expect(req.param('SortBy'), isNull);
      expect(req.param('SortOrder'), isNull);

      // 顺序与服务端下发完全一致（不做本地排序）
      expect(libs.map((l) => l.id).toList(), ['L2', 'L1', 'L3']);
      expect(
        libs.map((l) => l.name).toList(),
        ['动画电影', '华语电影', '外语电影'],
      );

      // 服务器给了 Primary tag 则拼入封面 URL，没有则不带 tag 参数
      expect(libs[0].posterUrl, contains('&tag=tag-2'));
      expect(libs[1].posterUrl, isNot(contains('tag=')));
      expect(libs[2].posterUrl, isNot(contains('tag=')));
    });

    test('无效条目（缺名/缺 id）被过滤且不影响其余顺序', () async {
      respondWith = (_) => {
            'Items': [
              {'Name': '', 'ItemId': 'Lx'},
              {'Name': '华语电影', 'Id': 'L1'},
              {'Name': '无ID'},
            ],
          };

      final libs = await service.getLibraries();
      expect(libs.map((l) => l.id).toList(), ['L1']);
    });
  });

  group('getSeasons 剧集季列表', () {
    test('请求 /Shows/{id}/Seasons 且带 UserId/Fields', () async {
      respondWith = (_) => {
            'Items': [
              {
                'Id': 'sea1',
                'Name': '第1季',
                'Type': 'Season',
                'IndexNumber': 1,
                'ChildCount': 6,
                'ImageTags': {'Primary': 'tag-s1'},
              },
              {
                'Id': 'sea2',
                'Name': '第2季',
                'Type': 'Season',
                'IndexNumber': 2,
                'ChildCount': 8,
              },
            ],
          };

      final seasons = await service.getSeasons('sv1');

      final req = captured.single;
      expect(req.path, '/Shows/sv1/Seasons');
      expect(req.param('UserId'), 'user-1');
      expect(req.param('Fields'), 'ImageTags,ChildCount');

      expect(seasons, hasLength(2));
      expect(seasons[0].id, 'sea1');
      expect(seasons[0].childCount, 6);
      expect(seasons[0].posterUrl, contains('/Items/sea1/Images/Primary'));
      expect(seasons[0].posterUrl, contains('tag=tag-s1'));
      expect(seasons[1].childCount, 8);
      expect(seasons[1].posterUrl, isNull, reason: '无 Primary tag 则无海报');
    });

    test('空 Items 返回空列表', () async {
      final seasons = await service.getSeasons('sv1');
      expect(seasons, isEmpty);
    });

    test('请求失败（401 除外）返回空列表不抛错', () async {
      final unreachable = EmbyService();
      unreachable.configure(
        serverUrl: 'http://127.0.0.1:1',
        accessToken: 't',
        userId: 'u',
        serverId: 's',
      );

      expect(await unreachable.getSeasons('sv1'), isEmpty);
    });
  });

  group('getItemCounts 电影/电视剧/集计数', () {
    test('优先走 /Items/Counts 专用端点，一次请求解析三个计数', () async {
      respondWith = (_) => {
            'MovieCount': 2565,
            'SeriesCount': 2415,
            'EpisodeCount': 73462,
          };

      final counts = await service.getItemCounts();

      expect(counts, isNotNull);
      expect(counts!.movies, 2565);
      expect(counts.series, 2415);
      expect(counts.episodes, 73462);

      // 只发一个请求，命中专用端点
      expect(captured, hasLength(1));
      expect(captured.single.path, '/Items/Counts');
      expect(captured.single.param('UserId'), 'user-1');
    });

    test('Counts 端点缺字段时回退 /Items 并读 TotalRecordCount', () async {
      respondWith = (_) => {'TotalRecordCount': 42};

      final counts = await service.getItemCounts();

      expect(counts, isNotNull);
      expect(counts!.movies, 42);
      expect(counts.series, 42);
      expect(counts.episodes, 42);

      // 1 次 Counts（缺字段） + 3 次 /Items 回退
      expect(captured, hasLength(4));
      expect(captured.first.path, '/Items/Counts');
      final itemsRequests = captured.skip(1).toList();
      expect(
        itemsRequests.map((r) => r.param('IncludeItemTypes')).toSet(),
        {'Movie', 'Series', 'Episode'},
      );
      for (final r in itemsRequests) {
        expect(r.path, '/Items');
        expect(r.param('Limit'), '1');
        expect(r.param('Recursive'), 'true');
      }
    });

    test('回退路径兼容旧键名 TotalRecords', () async {
      respondWith = (_) => {'TotalRecords': 7};

      final counts = await service.getItemCounts();
      expect(counts, isNotNull);
      expect(counts!.movies, 7);
      expect(counts.series, 7);
      expect(counts.episodes, 7);
    });

    test('两个端点都缺计数字段时按 0 计', () async {
      respondWith = (_) => {'Items': <dynamic>[]};

      final counts = await service.getItemCounts();
      expect(counts, isNotNull);
      expect(counts!.movies, 0);
      expect(counts.series, 0);
      expect(counts.episodes, 0);
    });

    test('连接失败返回 null 不抛错（统计不阻塞调用方）', () async {
      final unreachable = EmbyService();
      unreachable.configure(
        serverUrl: 'http://127.0.0.1:1',
        accessToken: 't',
        userId: 'u',
        serverId: 's',
      );

      expect(await unreachable.getItemCounts(), isNull);
    });
  });

  group('收藏接口', () {
    test('setFavorite(true) 走 POST /Users/{id}/FavoriteItems/{itemId}',
        () async {
      final ok = await service.setFavorite('item-9', true);
      expect(ok, isTrue);
      final req = captured.single;
      expect(req.method, 'POST');
      expect(req.path, '/Users/user-1/FavoriteItems/item-9');
    });

    test('setFavorite(false) 走 DELETE 同路径', () async {
      final ok = await service.setFavorite('item-9', false);
      expect(ok, isTrue);
      final req = captured.single;
      expect(req.method, 'DELETE');
      expect(req.path, '/Users/user-1/FavoriteItems/item-9');
    });

    test('getFavoriteItems 带 Filters=IsFavorite 且限定类型', () async {
      await service.getFavoriteItems();
      final req = captured.single;
      expect(req.path, '/Items');
      expect(req.param('Filters'), 'IsFavorite');
      expect(req.param('IncludeItemTypes'), 'Movie,Series,Episode');
      expect(req.param('Recursive'), 'true');
    });

    test('getFavoriteItems 解析 UserData.IsFavorite', () async {
      respondWith = (_) => {
            'Items': [
              {
                'Id': 'm1',
                'Name': '收藏电影',
                'Type': 'Movie',
                'UserData': {'IsFavorite': true},
              },
            ],
          };
      final items = await service.getFavoriteItems();
      expect(items, hasLength(1));
      expect(items.single.id, 'm1');
      expect(items.single.isFavorite, isTrue);
    });
  });

  group('已观看接口', () {
    test('setWatched(true) 走 POST /Users/{id}/PlayedItems/{itemId}', () async {
      final ok = await service.setWatched('item-9', true);
      expect(ok, isTrue);
      final req = captured.single;
      expect(req.method, 'POST');
      expect(req.path, '/Users/user-1/PlayedItems/item-9');
    });

    test('setWatched(false) 走 DELETE 同路径', () async {
      final ok = await service.setWatched('item-9', false);
      expect(ok, isTrue);
      final req = captured.single;
      expect(req.method, 'DELETE');
      expect(req.path, '/Users/user-1/PlayedItems/item-9');
    });
  });

  group('继续观看接口', () {
    test('getResumeItems 请求 /Items/Resume 且带 MediaTypes=Video', () async {
      await service.getResumeItems(limit: 8);
      final req = captured.single;
      expect(req.path, '/Users/user-1/Items/Resume');
      expect(req.param('MediaTypes'), 'Video');
      expect(req.param('Limit'), '8');
    });

    test('getResumeItems 解析进度字段', () async {
      respondWith = (_) => {
            'Items': [
              {
                'Id': 'e1',
                'Name': '第1集',
                'Type': 'Episode',
                'UserData': {
                  'PlaybackPositionTicks': 1690000000,
                  'PlayedPercentage': 10.0,
                },
              },
            ],
          };
      final items = await service.getResumeItems();
      expect(items, hasLength(1));
      expect(items.single.playbackPositionMs, 169000);
    });
  });

  group('播放会话上报', () {
    test('reportPlaybackStart → POST /Sessions/Playing（PositionTicks=ms×10000）',
        () async {
      await service.reportPlaybackStart(
        itemId: 'i1',
        playSessionId: 'ps1',
        mediaSourceId: 'ms1',
        positionMs: 1000,
      );
      final req = captured.single;
      expect(req.method, 'POST');
      expect(req.path, '/Sessions/Playing');
      expect(req.body['ItemId'], 'i1');
      expect(req.body['MediaSourceId'], 'ms1');
      expect(req.body['PositionTicks'], 1000 * 10000);
      expect(req.body['PlaySessionId'], 'ps1');
    });

    test('reportPlaybackProgress → /Sessions/Playing/Progress（含 IsPaused）',
        () async {
      await service.reportPlaybackProgress(
        itemId: 'i1',
        playSessionId: 'ps1',
        positionMs: 2000,
        isPaused: true,
      );
      final req = captured.single;
      expect(req.path, '/Sessions/Playing/Progress');
      expect(req.body['PositionTicks'], 2000 * 10000);
      expect(req.body['IsPaused'], isTrue);
    });

    test('reportPlaybackStopped → /Sessions/Playing/Stopped', () async {
      await service.reportPlaybackStopped(
        itemId: 'i1',
        playSessionId: 'ps1',
        positionMs: 3000,
      );
      final req = captured.single;
      expect(req.path, '/Sessions/Playing/Stopped');
      expect(req.body['PositionTicks'], 3000 * 10000);
    });

    test('getPlaySessionId → POST PlaybackInfo 解析 PlaySessionId', () async {
      respondWith = (_) => {'PlaySessionId': 'ps-abc', 'MediaSources': []};
      final id = await service.getPlaySessionId(
        itemId: 'i1',
        mediaSourceId: 'ms1',
      );
      expect(id, 'ps-abc');
      final req = captured.single;
      expect(req.method, 'POST');
      expect(req.path, '/Items/i1/PlaybackInfo');
      expect(req.param('MediaSourceId'), 'ms1');
    });

    test('getPlaySessionId 缺字段 → null', () async {
      respondWith = (_) => {'MediaSources': []};
      expect(await service.getPlaySessionId(itemId: 'i1'), isNull);
    });
  });

  group('相似推荐接口', () {
    test('getSimilarItems 带 UserId（否则 Emby 返回空）', () async {
      await service.getSimilarItems('i1');
      final req = captured.single;
      expect(req.path, '/Items/i1/Similar');
      expect(req.param('UserId'), 'user-1');
    });
  });
}

/// 忽略未使用的 future，避免 lint 告警。
void unawaited(Future<void> future) {}

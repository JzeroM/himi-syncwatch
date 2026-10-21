import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
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

  /// 可按测试用例替换的响应体生成器（默认空 Items）；按请求路径区分。
  late Object Function(String path) respondWith;

  /// 可按测试用例替换的状态码生成器（默认 200；404 模拟端点不存在）。
  late int Function(String path) statusFor;

  setUp(() async {
    captured = <_CapturedRequest>[];
    respondWith = (_) => {'Items': <dynamic>[]};
    statusFor = (_) => HttpStatus.ok;
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
        final status = statusFor(request.uri.path);
        request.response.statusCode = status;
        if (status == HttpStatus.ok) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(respondWith(request.uri.path)));
        }
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

  group('getItems 筛选参数透传', () {
    test('四参数按 Emby 约定分隔符进入查询串', () async {
      await service.getItems(
        parentId: 'lib-1',
        filters: 'IsUnplayed',
        genres: '动作|科幻',
        years: '2023,2024',
        officialRatings: 'PG-13|R',
      );

      final req = captured.single;
      expect(req.param('Filters'), 'IsUnplayed');
      expect(req.param('Genres'), '动作|科幻', reason: 'Genres 多选为管道符分隔');
      expect(req.param('Years'), '2023,2024', reason: 'Years 多选为逗号分隔');
      expect(req.param('OfficialRatings'), 'PG-13|R');
    });

    test('未传/空筛选参数时不注入对应查询键', () async {
      await service.getItems(parentId: 'lib-1');
      var req = captured.single;
      expect(req.param('Filters'), isNull);
      expect(req.param('Genres'), isNull);
      expect(req.param('Years'), isNull);
      expect(req.param('OfficialRatings'), isNull);

      captured.clear();
      await service.getItems(parentId: 'lib-1', filters: '', genres: '');
      req = captured.single;
      expect(req.param('Filters'), isNull);
      expect(req.param('Genres'), isNull);
    });
  });

  group('getFilterOptions 可选项解析与兜底合并', () {
    test('四路并行请求，聚合端点 + 专用端点合并去重排序', () async {
      respondWith = (path) {
        switch (path) {
          case '/Items/Filters':
            return {
              'Genres': [
                {'Name': '动作', 'Id': 'g1'},
                '科幻',
              ],
              'Years': [2023, 2024],
              'OfficialRatings': [
                'PG-13',
                {'Name': 'R'}
              ],
            };
          case '/Genres':
            return {
              'Items': [
                {'Name': '动作', 'Id': 'g1'},
                {'Name': '喜剧'},
              ],
            };
          case '/Years':
            return {
              'Items': [
                {'Name': '2024', 'Id': 'y2024'},
                {'Name': '2022', 'Id': 'y2022'},
                {'Name': '2021', 'Id': 'y2021'},
              ],
            };
          case '/OfficialRatings':
            return {
              'Items': [
                {'Name': 'R'},
                {'Name': 'G', 'Id': 'g'},
              ],
            };
          default:
            return {'Items': <dynamic>[]};
        }
      };

      final options = await service.getFilterOptions(
        parentId: 'lib-1',
        includeItemTypes: 'Movie',
      );

      expect(options.genres, ['动作', '喜剧', '科幻'], reason: '合并去重后字母序');
      expect(options.years, [2024, 2023, 2022, 2021], reason: '合并去重后降序');
      expect(options.ratings, ['G', 'PG-13', 'R']);

      expect(captured, hasLength(4), reason: '聚合 + 三个专用端点');
      expect(
        captured.map((r) => r.path).toSet(),
        {'/Items/Filters', '/Genres', '/Years', '/OfficialRatings'},
      );
      for (final req in captured) {
        expect(req.param('ParentId'), 'lib-1');
        expect(req.param('IncludeItemTypes'), 'Movie');
        expect(req.param('UserId'), 'user-1');
      }
    });

    test('聚合端点 404 → 三个专用端点兜底仍有可选项', () async {
      statusFor = (path) =>
          path == '/Items/Filters' ? HttpStatus.notFound : HttpStatus.ok;
      respondWith = (path) {
        switch (path) {
          case '/Genres':
            return {
              'Items': [
                {'Name': '动作'},
              ],
            };
          case '/Years':
            return {
              'Items': [
                {'Name': '2024', 'Id': 'y'},
              ],
            };
          default:
            return {'Items': <dynamic>[]};
        }
      };

      final options = await service.getFilterOptions(parentId: 'lib-1');

      expect(options.genres, ['动作']);
      expect(options.years, [2024]);
      expect(options.ratings, isEmpty);
    });

    test('年份项 Id 非数字时按 Name 解析不丢（Emby 真实结构）', () async {
      statusFor = (path) =>
          path == '/Items/Filters' ? HttpStatus.notFound : HttpStatus.ok;
      respondWith = (path) {
        switch (path) {
          case '/Years':
            return {
              'Items': [
                {'Name': '2024', 'Id': '0f8c-non-numeric'},
              ],
            };
          default:
            return {'Items': <dynamic>[]};
        }
      };

      final options = await service.getFilterOptions();

      expect(options.years, [2024], reason: 'Name 优先于非数字 Id');
    });

    test('专用端点全 404 → /Items 扫描兜底聚合年份/分级', () async {
      statusFor =
          (path) => path == '/Items' ? HttpStatus.ok : HttpStatus.notFound;
      respondWith = (path) {
        if (path == '/Items') {
          return {
            'Items': [
              {'ProductionYear': 2024, 'OfficialRating': 'PG-13'},
              {'ProductionYear': 2020, 'OfficialRating': 'R'},
              {'ProductionYear': 2024, 'OfficialRating': 'R'},
            ],
          };
        }
        return {'Items': <dynamic>[]};
      };

      final options = await service.getFilterOptions(
        parentId: 'lib-1',
        includeItemTypes: 'Movie',
      );

      expect(options.years, [2024, 2020], reason: '去重降序');
      expect(options.ratings, ['PG-13', 'R']);
    });

    test('全部端点失败 → 空对象不抛错（面板降级）', () async {
      statusFor = (_) => HttpStatus.notFound;

      final options = await service.getFilterOptions();

      expect(options.isEmpty, isTrue);
      expect(options.genres, isEmpty);
      expect(options.years, isEmpty);
      expect(options.ratings, isEmpty);
    });

    test('缺失字段 → 空列表且 isEmpty', () async {
      respondWith = (_) => <String, dynamic>{};
      final options = await service.getFilterOptions();
      expect(options.isEmpty, isTrue);
      expect(options.genres, isEmpty);
      expect(options.years, isEmpty);
      expect(options.ratings, isEmpty);
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
      expect(fields, contains('Chapters'));
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

    test('请求失败（401 除外）抛 EmbyException（v1.2.19）', () async {
      final unreachable = EmbyService();
      unreachable.configure(
        serverUrl: 'http://127.0.0.1:1',
        accessToken: 't',
        userId: 'u',
        serverId: 's',
      );

      await expectLater(
        unreachable.getSeasons('sv1'),
        throwsA(isA<EmbyException>()),
      );
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
      expect(req.param('SortBy'), 'SortName');
      expect(req.param('SortOrder'), 'Ascending');
    });

    test('getFavoriteItems 筛选/排序参数下传且 IsFavorite 前置合并', () async {
      await service.getFavoriteItems(
        includeItemTypes: 'Movie',
        sortBy: 'ProductionYear',
        sortOrder: 'Descending',
        filters: 'IsUnplayed',
        genres: '动作|科幻',
        years: '2024,2023',
        officialRatings: 'R',
      );
      final req = captured.single;
      expect(req.param('Filters'), 'IsFavorite,IsUnplayed',
          reason: '收藏恒为 IsFavorite，播放状态追加其后');
      expect(req.param('IncludeItemTypes'), 'Movie');
      expect(req.param('SortBy'), 'ProductionYear');
      expect(req.param('SortOrder'), 'Descending');
      expect(req.param('Genres'), '动作|科幻');
      expect(req.param('Years'), '2024,2023');
      expect(req.param('OfficialRatings'), 'R');
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

    test('removeFromResume 走 HideFromResume 且附带清空进度', () async {
      final ok = await service.removeFromResume('item-9');
      expect(ok, isTrue);
      expect(captured, hasLength(2));
      final hide = captured[0];
      expect(hide.method, 'POST');
      expect(hide.path, '/Users/user-1/Items/item-9/HideFromResume');
      expect(hide.param('Hide'), 'true');
      final clear = captured[1];
      expect(clear.method, 'POST');
      expect(clear.path, '/Users/user-1/Items/item-9/UserData');
      expect(clear.body['PlaybackPositionTicks'], 0);
    });

    test('getLibraryPlaybackSettings 解析按库阈值（ItemId + LibraryOptions）',
        () async {
      respondWith = (path) => path == '/Library/VirtualFolders/Query'
          ? [
              {
                'ItemId': 'lib-1',
                'LibraryOptions': {
                  'MinResumePct': 5,
                  'MaxResumePct': 95,
                  'MinResumeDurationSeconds': 10,
                },
              },
              {
                'ItemId': 'lib-2',
                'LibraryOptions': {'MaxResumePct': 80},
              },
            ]
          : <dynamic>[];
      final map = await service.getLibraryPlaybackSettings();
      expect(map.keys, containsAll(['lib-1', 'lib-2']));
      expect(map['lib-1']!.minResumePct, 5);
      expect(map['lib-1']!.maxResumePct, 95);
      expect(map['lib-1']!.minResumeDurationSeconds, 10);
      expect(map['lib-2']!.maxResumePct, 80);
      expect(map['lib-2']!.minResumePct, 1);
    });

    test('getGlobalPlaybackSettings 解析 /System/Configuration', () async {
      respondWith = (path) => path == '/System/Configuration'
          ? {
              'MinResumePct': 2,
              'MaxResumePct': 88,
              'MinResumeDurationSeconds': 6,
            }
          : <String, dynamic>{};
      final s = await service.getGlobalPlaybackSettings();
      expect(s.minResumePct, 2);
      expect(s.maxResumePct, 88);
      expect(s.minResumeDurationSeconds, 6);
    });

    test('getAncestorIds 解析 /Items/{id}/Ancestors 的 Id 列表', () async {
      respondWith = (path) => path == '/Items/i1/Ancestors'
          ? [
              {'Id': 'season-1'},
              {'Id': 'series-1'},
              {'Id': 'lib-1'},
            ]
          : <dynamic>[];
      final ids = await service.getAncestorIds('i1');
      expect(ids, ['season-1', 'series-1', 'lib-1']);
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

  group('getLibraryCounts', () {
    test('成功：Counts 端点 + /Items（无 UserId）各返回计数', () async {
      respondWith = (path) {
        if (path == '/Items/Counts') {
          return {
            'MovieCount': 100,
            'SeriesCount': 200,
            'EpisodeCount': 300,
          };
        }
        // /Items 按 IncludeItemTypes 区分
        return {'TotalRecordCount': 999};
      };

      final counts = await service.getLibraryCounts();

      expect(counts, isNotNull);
      expect(counts!.withoutVersions, isNotNull);
      expect(counts.withoutVersions!.movies, 100);
      expect(counts.withoutVersions!.series, 200);
      expect(counts.withoutVersions!.episodes, 300);
      expect(counts.withVersions, isNotNull);
      expect(counts.withVersions!.movies, 999);
      expect(counts.withVersions!.series, 999);
      expect(counts.withVersions!.episodes, 999);

      // 1 次 Counts + 3 次 /Items（无 UserId）
      expect(captured, hasLength(4));
      final countsReq = captured.first;
      expect(countsReq.path, '/Items/Counts');
      expect(countsReq.param('UserId'), 'user-1');
      final itemsReqs = captured.skip(1).toList();
      for (final r in itemsReqs) {
        expect(r.path, '/Items');
        expect(r.param('UserId'), isNull);
        expect(r.param('Limit'), '1');
        expect(r.param('Recursive'), 'true');
      }
      expect(
        itemsReqs.map((r) => r.param('IncludeItemTypes')).toSet(),
        {'Movie', 'Series', 'Episode'},
      );
    });

    test('Counts 失败但 /Items 成功：withoutVersions null，withVersions 有值', () async {
      statusFor = (path) => path == '/Items/Counts' ? 404 : HttpStatus.ok;
      respondWith = (_) => {'TotalRecordCount': 55};

      final counts = await service.getLibraryCounts();

      expect(counts, isNotNull);
      expect(counts!.withoutVersions, isNull);
      expect(counts.withVersions, isNotNull);
      expect(counts.withVersions!.movies, 55);
    });

    test('全部失败：返回 null', () async {
      statusFor = (_) => 500;

      final counts = await service.getLibraryCounts();
      expect(counts, isNull);
    });
  });

  group('getPlaybackInfo / STRM 直链解析', () {
    test('解析 PlaySessionId 与 MediaSources 直链字段', () async {
      respondWith = (_) => {
            'PlaySessionId': 'ps-1',
            'MediaSources': [
              {
                'Id': 'ms1',
                'Name': 'strm',
                'Path': 'http://cdn.example.com/movie.mkv',
                'DirectStreamUrl':
                    'http://cdn.example.com/direct/movie.mkv?token=abc',
                'Protocol': 'Http',
                'IsRemote': true,
              },
            ],
          };
      final info = await service.getPlaybackInfo(
        itemId: 'i1',
        mediaSourceId: 'ms1',
      );
      expect(info.playSessionId, 'ps-1');
      expect(info.sources, hasLength(1));
      final src = info.sources.single;
      expect(src.path, 'http://cdn.example.com/movie.mkv');
      expect(src.directStreamUrl,
          'http://cdn.example.com/direct/movie.mkv?token=abc');
      expect(src.protocol, 'Http');
      expect(src.isRemote, true);
      expect(info.sourceById('ms1')!.id, 'ms1');
    });

    test('sourceById 未命中/为空 → 回退首个源', () async {
      respondWith = (_) => {
            'MediaSources': [
              {'Id': 'a', 'Name': 'A'},
              {'Id': 'b', 'Name': 'B'},
            ],
          };
      final info = await service.getPlaybackInfo(itemId: 'i1');
      expect(info.sourceById('zzz')!.id, 'a');
      expect(info.sourceById(null)!.id, 'a');
    });

    test('resolveStrmDirectUrl 优先绝对 DirectStreamUrl', () {
      final src = MediaSource(
        id: 'ms1',
        name: 's',
        path: 'http://path.example.com/x.mkv',
        directStreamUrl: 'https://direct.example.com/y.mkv',
      );
      expect(
        resolveStrmDirectUrl(source: src, proxyUrl: 'http://proxy/stream'),
        'https://direct.example.com/y.mkv',
      );
    });

    test('resolveStrmDirectUrl DirectStreamUrl 相对 → 回退绝对 Path', () {
      final src = MediaSource(
        id: 'ms1',
        name: 's',
        path: 'http://path.example.com/x.mkv',
        directStreamUrl: '/Videos/1/stream?static=true',
      );
      expect(
        resolveStrmDirectUrl(source: src, proxyUrl: 'http://proxy/stream'),
        'http://path.example.com/x.mkv',
      );
    });

    test('resolveStrmDirectUrl 均不可用 → 回退代理 URL', () {
      final src = MediaSource(id: 'ms1', name: 's', path: '/local/file.mkv');
      expect(
        resolveStrmDirectUrl(source: src, proxyUrl: 'http://proxy/stream'),
        'http://proxy/stream',
      );
      expect(
        resolveStrmDirectUrl(source: null, proxyUrl: 'http://proxy/stream'),
        'http://proxy/stream',
      );
    });

    test('isAbsoluteHttpUrl 判定', () {
      expect(isAbsoluteHttpUrl('http://x'), isTrue);
      expect(isAbsoluteHttpUrl('HTTPS://X/Y'), isTrue);
      expect(isAbsoluteHttpUrl('/Videos/1'), isFalse);
      expect(isAbsoluteHttpUrl('file:///x'), isFalse);
      expect(isAbsoluteHttpUrl(null), isFalse);
      expect(isAbsoluteHttpUrl(''), isFalse);
    });
  });

  group('账号服务（改密 / 头像 URL）', () {
    test('changePassword → POST /Users/{userId}/Password + CurrentPw/NewPw',
        () async {
      await service.changePassword(
        currentPassword: 'old',
        newPassword: 'new123',
      );
      final req = captured.single;
      expect(req.method, 'POST');
      expect(req.path, '/Users/user-1/Password');
      expect(req.body['CurrentPw'], 'old');
      expect(req.body['NewPw'], 'new123');
    });

    test('getUserImageUrl 无 tag / 带 tag', () {
      expect(service.getUserImageUrl(),
          'http://127.0.0.1:${server.port}/Users/user-1/Images/Primary');
      expect(service.getUserImageUrl(tag: '123'),
          'http://127.0.0.1:${server.port}/Users/user-1/Images/Primary?tag=123');
    });
  });

  group('只读失败抛 EmbyException（v1.2.19 不再静默返回空）', () {
    test('非 401 的 5xx → EmbyException', () async {
      statusFor = (_) => HttpStatus.internalServerError;
      await expectLater(
        service.getLibraries(),
        throwsA(isA<EmbyException>()),
      );
    });

    test('连接失败 → EmbyException', () async {
      final dead = EmbyService();
      dead.configure(
        serverUrl: 'http://127.0.0.1:1',
        accessToken: 't',
        userId: 'u',
        serverId: 's',
      );
      await expectLater(
        dead.getItems(parentId: 'x'),
        throwsA(isA<EmbyException>()),
      );
    });

    test('401 仍 rethrow（鉴权失败不降级为 EmbyException）', () async {
      statusFor = (_) => HttpStatus.unauthorized;
      await expectLater(
        service.getLibraries(),
        throwsA(isA<DioException>()),
      );
    });

    test('计数类沿用 null=失败语义（getItemCounts 不抛错）', () async {
      statusFor = (_) => HttpStatus.internalServerError;
      expect(await service.getItemCounts(), isNull);
    });
  });
}

/// 忽略未使用的 future，避免 lint 告警。
void unawaited(Future<void> future) {}

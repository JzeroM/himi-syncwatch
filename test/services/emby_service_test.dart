import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 启动一个本地 HTTP 服务，捕获 EmbyService 发出的请求路径与查询参数。
class _CapturedRequest {
  final String path;
  final Map<String, List<String>> query;

  _CapturedRequest(this.path, this.query);

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
        captured.add(
          _CapturedRequest(request.uri.path, request.uri.queryParametersAll),
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
}

/// 忽略未使用的 future，避免 lint 告警。
void unawaited(Future<void> future) {}

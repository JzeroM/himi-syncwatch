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

  setUp(() async {
    captured = <_CapturedRequest>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    unawaited(() async {
      await for (final request in server) {
        captured.add(
          _CapturedRequest(request.uri.path, request.uri.queryParametersAll),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'Items': <dynamic>[]}));
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
}

/// 忽略未使用的 future，避免 lint 告警。
void unawaited(Future<void> future) {}

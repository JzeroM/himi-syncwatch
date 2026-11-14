import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_error.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 捕获 EmbyService 发出的请求方法/路径/查询参数。
class _CapturedRequest {
  _CapturedRequest(this.method, this.path, this.query);

  final String method;
  final String path;
  final Map<String, List<String>> query;

  String? param(String key) => query[key]?.first;
}

/// 仿「HX-NewEmby」这类 Spring 网关：接口不存在时返回 HTTP 200 +
/// `{"code":"-1","message":"No static resource ..."}`（Dio 不会抛异常）。
Map<String, dynamic> _springMissing(String path) => {
      'code': '-1',
      'message': 'No static resource $path.',
      'data': null,
      'desc': 'No static resource $path.',
    };

void main() {
  late HttpServer server;
  late List<_CapturedRequest> captured;
  late EmbyService service;

  late int Function(String method, String path) statusFor;
  late Object Function(String method, String path) respondWith;

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        await utf8.decoder.bind(request).join();
        captured.add(
          _CapturedRequest(
            request.method,
            request.uri.path,
            request.uri.queryParametersAll,
          ),
        );
        final status = statusFor(request.method, request.uri.path);
        request.response.statusCode = status;
        if (status == HttpStatus.ok) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(respondWith(request.method, request.uri.path)));
        }
        await request.response.close();
      }
    }());
  }

  setUp(() async {
    captured = <_CapturedRequest>[];
    statusFor = (_, __) => HttpStatus.ok;
    respondWith = (_, __) => {'Items': <dynamic>[]};
    await startServer();

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

  group('authenticate 兼容性', () {
    test('使用官方大小写 /Users/AuthenticateByName', () async {
      respondWith = (_, __) => {
            'User': {'Id': 'user-1', 'Name': 'mojito'},
            'AccessToken': 'token-1',
            'ServerId': 'server-1',
          };

      final result = await service.authenticate(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'mojito',
        password: 'pw',
        deviceId: 'd1',
      );

      expect(captured.single.method, 'POST');
      expect(captured.single.path, '/Users/AuthenticateByName');
      expect(result['AccessToken'], 'token-1');
    });

    test('200 + 业务错误体 → 抛可读 EmbyException（friendlyEmbyError 原样透出）',
        () async {
      respondWith = (_, __) => _springMissing('Users/AuthenticateByName');

      Object? error;
      try {
        await service.authenticate(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'mojito',
          password: 'pw',
          deviceId: 'd1',
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<EmbyException>());
      expect(friendlyEmbyError(error!), contains('标准 Emby'));
      expect(friendlyEmbyError(error), contains('/emby'));
    });
  });

  group('/Items 缺失时回退 /Users/{id}/Items', () {
    setUp(() {
      respondWith = (_, path) {
        if (path == '/Items') return _springMissing('Items');
        if (path == '/Users/user-1/Items') {
          return {
            'Items': [
              {'Id': 'tmdb_1_movie', 'Name': '测试电影', 'Type': 'Movie'},
            ],
            'TotalRecordCount': 1,
          };
        }
        return {'Items': <dynamic>[]};
      };
    });

    test('getItems 自动改打用户维度端点并返回条目', () async {
      final items = await service.getItems(parentId: 'lib-1', limit: 20);

      expect(items, hasLength(1));
      expect(items.single.name, '测试电影');
      expect(
        captured.map((r) => r.path).toList(),
        ['/Items', '/Users/user-1/Items'],
        reason: '先官方端点，识别到缺失后回退',
      );
      // 查询参数原样透传
      expect(captured.last.param('ParentId'), 'lib-1');
      expect(captured.last.param('Limit'), '20');
    });

    test('第二次调用不再请求根级 /Items（标志已记忆）', () async {
      await service.getItems(parentId: 'lib-1');
      captured.clear();

      await service.getItems(parentId: 'lib-1');

      expect(captured.single.path, '/Users/user-1/Items');
    });

    test('searchItems 同样回退且保留 searchTerm', () async {
      final items = await service.searchItems('coco');

      expect(items, hasLength(1));
      expect(captured.last.path, '/Users/user-1/Items');
      expect(captured.last.param('searchTerm'), 'coco');
    });

    test('getFavoriteItems 同样回退且保留 Filters=IsFavorite', () async {
      final items = await service.getFavoriteItems();

      expect(items, hasLength(1));
      expect(captured.last.path, '/Users/user-1/Items');
      expect(captured.last.param('Filters'), 'IsFavorite');
    });

    test('getItemCounts 回退端点读 TotalRecordCount', () async {
      // /Items/Counts 在这类网关上同样返回伪错误体 → 走三次 /Items 回退。
      respondWith = (_, path) {
        if (path == '/Items/Counts') return _springMissing('Items/Counts');
        if (path == '/Items') return _springMissing('Items');
        return {'Items': <dynamic>[], 'TotalRecordCount': 7};
      };

      final counts = await service.getItemCounts();

      expect(counts, isNotNull);
      expect(counts!.movies, 7);
      expect(counts.series, 7);
      expect(counts.episodes, 7);
      expect(captured.first.path, '/Items/Counts');
      expect(
        captured.where((r) => r.path == '/Users/user-1/Items').length,
        3,
        reason: '三个类型各回退一次',
      );
    });

    test('根级 /Items 返回 404 时也回退', () async {
      statusFor = (_, path) =>
          path == '/Items' ? HttpStatus.notFound : HttpStatus.ok;

      final items = await service.getItems();

      expect(items, hasLength(1));
      expect(captured.last.path, '/Users/user-1/Items');
    });
  });

  group('标准 Emby 不触发回退（回归保护）', () {
    test('/Items 正常返回 Items → 只请求一次且路径为 /Items', () async {
      respondWith = (_, __) => {
            'Items': [
              {'Id': 'm1', 'Name': '电影', 'Type': 'Movie'},
            ],
            'TotalRecordCount': 1,
          };

      final items = await service.getItems();

      expect(items, hasLength(1));
      expect(captured.single.path, '/Items');
      expect(captured.any((r) => r.path.startsWith('/Users/user-1/Items')),
          isFalse);
    });

    test('空列表（Items: []）不会被误判成端点缺失', () async {
      respondWith = (_, __) => {'Items': <dynamic>[], 'TotalRecordCount': 0};

      final items = await service.getItems();
      await service.getItems();

      expect(items, isEmpty);
      expect(captured.map((r) => r.path).toSet(), {'/Items'});
    });
  });
}

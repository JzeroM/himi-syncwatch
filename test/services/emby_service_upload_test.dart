import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// uploadUserImage 要求 body 为 base64 文本（Emby 规范），故用独立 harness
/// 捕获原始请求体并反解校验。
void main() {
  late HttpServer server;
  late EmbyService service;

  late String? lastPath;
  late String? lastContentType;
  late String lastBody;

  setUp(() async {
    lastPath = null;
    lastContentType = null;
    lastBody = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    unawaited(() async {
      await for (final request in server) {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        lastPath = request.uri.path;
        lastContentType = request.headers.contentType?.mimeType;
        lastBody = utf8.decode(bytes);
        request.response.statusCode = HttpStatus.noContent;
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

  test('uploadUserImage → POST /Users/{userId}/Images/Primary + base64 文本',
      () async {
    final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
    await service.uploadUserImage(bytes, contentType: 'image/png');

    expect(lastPath, '/Users/user-1/Images/Primary');
    expect(lastContentType, 'image/png');
    expect(base64Decode(lastBody), bytes,
        reason: 'body 应为 base64 文本，反解后等于原图字节');
  });

  test('uploadUserImage 默认 Content-Type = image/jpeg', () async {
    await service.uploadUserImage(Uint8List.fromList([1, 2, 3]));
    expect(lastPath, '/Users/user-1/Images/Primary');
    expect(lastContentType, 'image/jpeg');
    expect(base64Decode(lastBody), [1, 2, 3]);
  });

  test('getUserImageTag → 解析 PrimaryImageTag', () async {
    server.close(force: true);
    final tagServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => tagServer.close(force: true));
    unawaited(() async {
      await for (final request in tagServer) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'Id': 'user-1', 'PrimaryImageTag': 'tag-xyz'}));
        await request.response.close();
      }
    }());
    final svc = EmbyService();
    svc.configure(
      serverUrl: 'http://127.0.0.1:${tagServer.port}',
      accessToken: 'test-token',
      userId: 'user-1',
      serverId: 'server-1',
    );

    expect(await svc.getUserImageTag(), 'tag-xyz');
  });
}

void unawaited(Future<void> future) {}

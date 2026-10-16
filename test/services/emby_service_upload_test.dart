import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// uploadUserImage 发送二进制原图（非 JSON），故用独立 harness 捕获原始字节。
void main() {
  late HttpServer server;
  late EmbyService service;

  late String? lastPath;
  late String? lastContentType;
  late int bytesLength;
  int? lastContentLength;

  setUp(() async {
    lastPath = null;
    lastContentType = null;
    bytesLength = 0;
    lastContentLength = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    unawaited(() async {
      await for (final request in server) {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        lastPath = request.uri.path;
        lastContentType = request.headers.contentType?.mimeType;
        bytesLength = bytes.length;
        lastContentLength = request.headers.contentLength;
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

  test('uploadUserImage → POST /Users/{userId}/Images/Primary 二进制 + Content-Type',
      () async {
    final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
    await service.uploadUserImage(bytes, contentType: 'image/png');

    expect(lastPath, '/Users/user-1/Images/Primary');
    expect(lastContentType, 'image/png');
    expect(bytesLength, 128, reason: '应发送完整原图字节');
    expect(lastContentLength, 128);
  });

  test('uploadUserImage 默认 Content-Type = image/jpeg', () async {
    await service.uploadUserImage(Uint8List.fromList([1, 2, 3]));
    expect(lastPath, '/Users/user-1/Images/Primary');
    expect(lastContentType, 'image/jpeg');
    expect(bytesLength, 3);
  });
}

void unawaited(Future<void> future) {}

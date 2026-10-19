import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/update/update_service.dart';

typedef _Handler = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final _Handler handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Object payload) => ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

ResponseBody _bytesBody(
  List<int> bytes, {
  int status = 200,
  Map<String, List<String>>? headers,
}) =>
    ResponseBody(
      Stream.fromIterable([Uint8List.fromList(bytes)]),
      status,
      headers: headers ??
          {
            Headers.contentLengthHeader: ['${bytes.length}'],
          },
    );

Map<String, dynamic> _listJson(List<Map<String, dynamic>> files) => {
      'status': 200,
      'data': {'content': files, 'total': files.length},
    };

Map<String, dynamic> _file(String name,
        {int size = 0, String? md5}) =>
    {
      'name': name,
      'size': size,
      if (md5 != null) 'hash_info': {'md5': md5},
    };

UpdateService _service(_Handler handler, {String? baseUrl}) {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(handler);
  return UpdateService(baseUrl: baseUrl ?? 'https://rink.eu.org', dio: dio);
}

void main() {
  group('parseRemoteAsset（文件名解析）', () {
    test('Android 三种 ABI + universal', () {
      final arm = parseRemoteAsset('himi-sync-1.2.30-arm64-v8a.apk')!;
      expect(arm.version, '1.2.30');
      expect(arm.target, UpdateTarget.android);
      expect(arm.abi, 'arm64-v8a');

      expect(
        parseRemoteAsset('himi-sync-1.2.30-armeabi-v7a.apk')!.abi,
        'armeabi-v7a',
      );
      expect(
        parseRemoteAsset('himi-sync-1.2.30-x86_64.apk')!.abi,
        'x86_64',
      );
      expect(
        parseRemoteAsset('himi-sync-1.2.30-universal.apk')!.abi,
        'universal',
      );
    });

    test('Windows setup / iOS ipa', () {
      final win = parseRemoteAsset('himi-sync-windows-1.2.30-setup.exe')!;
      expect(win.target, UpdateTarget.windows);
      expect(win.version, '1.2.30');

      final ios = parseRemoteAsset('himi-sync-ios-unsigned-1.2.30.ipa')!;
      expect(ios.target, UpdateTarget.ios);
      expect(ios.version, '1.2.30');
    });

    test('大小与 md5 透传；不匹配的名字返回 null', () {
      final a = parseRemoteAsset(
        'himi-sync-1.2.30-arm64-v8a.apk',
        size: 123,
        md5: 'ABCD',
      )!;
      expect(a.size, 123);
      expect(a.md5, 'ABCD');

      expect(parseRemoteAsset('himi-sync-1.2.30.apk'), isNull);
      expect(parseRemoteAsset('himi-sync-windows-1.2.30.zip'), isNull);
      expect(parseRemoteAsset('himi-sync-windows-1.2.30-setup.exe.sha256'), isNull);
      expect(parseRemoteAsset('other-1.2.30-arm64-v8a.apk'), isNull);
      expect(parseRemoteAsset('himi-sync-1.2-arm64-v8a.apk'), isNull);
      expect(parseRemoteAsset(''), isNull);
    });
  });

  group('compareVersions（版本比较）', () {
    test('数值比较而非字符串', () {
      expect(compareVersions('1.2.9', '1.2.10'), -1);
      expect(compareVersions('1.2.10', '1.2.9'), 1);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('相等（忽略 v 前缀与 +build 后缀）', () {
      expect(compareVersions('1.2.30', '1.2.30'), 0);
      expect(compareVersions('v1.2.30', '1.2.30'), 0);
      expect(compareVersions('1.2.30+456', '1.2.30'), 0);
    });

    test('段数不足按 0 处理', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.1'), -1);
    });
  });

  group('assetsFromListJson（列表 API 解析）', () {
    test('真实结构：只保留认识的包，忽略文件夹/ipa 之外的文件', () {
      final assets = assetsFromListJson(_listJson([
        _file('himi-sync-1.2.29-arm64-v8a.apk', size: 111526386, md5: 'AA'),
        _file('himi-sync-windows-1.2.29-setup.exe', size: 76116677),
        _file('himi-sync-ios-unsigned-1.2.29.ipa', size: 50733352),
        _file('README.txt'),
        _file('himi-sync-1.2.29'),
      ]));
      expect(assets.length, 3);
      expect(assets.first.version, '1.2.29');
      expect(assets.first.md5, 'AA');
      expect(assets.first.size, 111526386);
    });

    test('非法结构返回空列表', () {
      expect(assetsFromListJson(null), isEmpty);
      expect(assetsFromListJson('x'), isEmpty);
      expect(assetsFromListJson(const {}), isEmpty);
      expect(assetsFromListJson(const {'data': 1}), isEmpty);
      expect(assetsFromListJson(const {'data': {}}), isEmpty);
      expect(assetsFromListJson(const {'data': {'content': 'x'}}), isEmpty);
    });
  });

  group('latestAssetFor（挑选最高版本 + ABI 匹配）', () {
    final assets = [
      parseRemoteAsset('himi-sync-1.2.29-arm64-v8a.apk')!,
      parseRemoteAsset('himi-sync-1.2.30-arm64-v8a.apk')!,
      parseRemoteAsset('himi-sync-1.2.30-armeabi-v7a.apk')!,
      parseRemoteAsset('himi-sync-1.2.31-universal.apk')!,
      parseRemoteAsset('himi-sync-windows-9.9.9-setup.exe')!,
    ];

    test('取版本最高，不受平台外资产干扰', () {
      final a = latestAssetFor(
        assets: assets,
        target: UpdateTarget.android,
        supportedAbis: const ['arm64-v8a'],
      )!;
      expect(a.version, '1.2.31');
      expect(a.abi, 'universal');
    });

    test('设备 ABI 优先于版本兜底（同版本内按 ABI 顺序）', () {
      final onlyV30 = assets.where((a) => a.version == '1.2.30').toList();
      expect(
        latestAssetFor(
          assets: onlyV30,
          target: UpdateTarget.android,
          supportedAbis: const ['armeabi-v7a', 'arm64-v8a'],
        )!.abi,
        'armeabi-v7a',
      );
      expect(
        latestAssetFor(
          assets: onlyV30,
          target: UpdateTarget.android,
          supportedAbis: const ['arm64-v8a'],
        )!.abi,
        'arm64-v8a',
      );
    });

    test('设备 ABI 列表不匹配时按 arm64 → v7a → universal 回退', () {
      final v29 = [parseRemoteAsset('himi-sync-1.2.29-universal.apk')!];
      expect(
        latestAssetFor(
          assets: v29,
          target: UpdateTarget.android,
          supportedAbis: const ['armeabi-v7a'],
        )!.abi,
        'universal',
      );
    });

    test('Windows 目标只看 setup.exe；无匹配返回 null', () {
      expect(
        latestAssetFor(assets: assets, target: UpdateTarget.windows)!.version,
        '9.9.9',
      );
      expect(latestAssetFor(assets: assets, target: UpdateTarget.ios), isNull);
    });
  });

  group('UpdateService.check', () {
    test('有更高版本 → available + 资产含下载地址', () async {
      final service = _service((options) async {
        expect(options.uri.path, '/api/fs/list');
        expect((options.data as Map)['path'], '/PACKAGES');
        return _jsonBody(_listJson([
          _file('himi-sync-1.2.30-arm64-v8a.apk', size: 10, md5: 'AA'),
        ]));
      });
      final result = await service.check(
        currentVersion: '1.2.29',
        target: UpdateTarget.android,
        supportedAbis: const ['arm64-v8a'],
      );
      expect(result.status, UpdateStatus.available);
      expect(result.asset!.version, '1.2.30');
      expect(result.currentVersion, '1.2.29');
      expect(service.downloadUrl(result.asset!.name),
          'https://rink.eu.org/d/PACKAGES/himi-sync-1.2.30-arm64-v8a.apk');
      expect(result.browseUrl, 'https://rink.eu.org/PACKAGES');
    });

    test('同版本/更低版本 → upToDate', () async {
      final service = _service((_) async => _jsonBody(_listJson([
            _file('himi-sync-1.2.29-arm64-v8a.apk'),
          ])));
      final result = await service.check(
        currentVersion: '1.2.29',
        target: UpdateTarget.android,
        supportedAbis: const ['arm64-v8a'],
      );
      expect(result.status, UpdateStatus.upToDate);
    });

    test('网络失败 → failed（静默，不抛异常）', () async {
      final service = _service((_) async => throw DioException(
            requestOptions: RequestOptions(path: '/api/fs/list'),
            error: 'boom',
          ));
      final result = await service.check(
        currentVersion: '1.2.29',
        target: UpdateTarget.android,
      );
      expect(result.status, UpdateStatus.failed);
      expect(result.error, isNotNull);
    });

    test('baseUrl 尾部斜杠归一', () {
      expect(UpdateService.normalizeBaseUrl('https://a.b/'), 'https://a.b');
      expect(UpdateService.normalizeBaseUrl(' https://a.b/// '), 'https://a.b');
    });
  });

  group('UpdateService.download', () {
    late Directory dir;
    final content = List<int>.generate(4096, (i) => i % 251);
    final contentMd5 = md5.convert(content).toString().toUpperCase();
    final asset = RemoteAsset(
      name: 'himi-sync-1.2.30-arm64-v8a.apk',
      version: '1.2.30',
      target: UpdateTarget.android,
      abi: 'arm64-v8a',
      size: content.length,
      md5: contentMd5,
    );

    setUp(() {
      dir = Directory.systemTemp.createTempSync('himi_update_test');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('下载并校验 MD5 成功', () async {
      final service = _service((_) async => _bytesBody(content));
      final file = await service.download(asset, dir: dir);
      expect(file.readAsBytesSync(), content);
      expect(file.path, endsWith('/updates/${asset.name}'));
    });

    test('已有部分文件时带 Range 续传（206）', () async {
      final updates = Directory('${dir.path}/updates')..createSync();
      File('${updates.path}/${asset.name}')
          .writeAsBytesSync(content.sublist(0, 1000));

      final service = _service((options) async {
        expect(options.headers['Range'], 'bytes=1000-');
        final rest = content.sublist(1000);
        return _bytesBody(
          rest,
          status: 206,
          headers: {
            'content-range': [
              'bytes 1000-${content.length - 1}/${content.length}',
            ],
            Headers.contentLengthHeader: ['${rest.length}'],
          },
        );
      });
      final file = await service.download(asset, dir: dir);
      expect(file.readAsBytesSync(), content);
    });

    test('服务端忽略 Range 返回 200 → 从头重写', () async {
      final updates = Directory('${dir.path}/updates')..createSync();
      File('${updates.path}/${asset.name}')
          .writeAsBytesSync(content.sublist(0, 1000));

      final service = _service((_) async => _bytesBody(content));
      final file = await service.download(asset, dir: dir);
      expect(file.readAsBytesSync(), content);
    });

    test('403（签名链接过期）自动重取链接后续传成功', () async {
      var call = 0;
      final service = _service((_) async {
        call++;
        if (call == 1) {
          return _bytesBody(const [], status: 403);
        }
        return _bytesBody(content);
      });
      final file = await service.download(asset, dir: dir);
      expect(call, 2);
      expect(file.readAsBytesSync(), content);
    });

    test('MD5 不匹配抛错并删除文件', () async {
      final badAsset = RemoteAsset(
        name: asset.name,
        version: asset.version,
        target: asset.target,
        size: content.length,
        md5: 'deadbeef',
      );
      final service = _service((_) async => _bytesBody(content));
      await expectLater(
        service.download(badAsset, dir: dir),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(File('${dir.path}/updates/${asset.name}').existsSync(), isFalse);
    });

    test('未知大小（size=0）也能下载（无 MD5 时跳过校验）', () async {
      final noHash = RemoteAsset(
        name: asset.name,
        version: asset.version,
        target: asset.target,
      );
      final service = _service((_) async => _bytesBody(content));
      final file = await service.download(noHash, dir: dir);
      expect(file.readAsBytesSync(), content);
    });
  });
}

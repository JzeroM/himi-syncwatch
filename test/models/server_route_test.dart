import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/server_route.dart';

void main() {
  group('ServerRoute 序列化', () {
    test('toJson/fromJson 往返一致', () {
      const r = ServerRoute(
        id: 'rt_1',
        name: '备用',
        url: 'https://b.example.com:8096',
        isReverseProxy: true,
      );
      final back = ServerRoute.fromJson(r.toJson());
      expect(back.id, 'rt_1');
      expect(back.name, '备用');
      expect(back.url, 'https://b.example.com:8096');
      expect(back.isReverseProxy, true);
    });

    test('fromJson 缺字段回退默认值', () {
      final r = ServerRoute.fromJson(const {});
      expect(r.id, '');
      expect(r.name, '');
      expect(r.url, '');
      expect(r.isReverseProxy, false);
    });

    test('defaultName 从 Route N 递增且防重', () {
      expect(ServerRoute.defaultName(const []), 'Route 1');
      final existing = [
        const ServerRoute(id: 'a', name: 'Route 1', url: 'u1'),
        const ServerRoute(id: 'b', name: 'Route 2', url: 'u2'),
      ];
      expect(ServerRoute.defaultName(existing), 'Route 3');
      final gap = [
        const ServerRoute(id: 'a', name: 'Route 1', url: 'u1'),
        const ServerRoute(id: 'b', name: 'Route 3', url: 'u3'),
      ];
      // 从 length+1=3 起，3 已占用 → 4
      expect(ServerRoute.defaultName(gap), 'Route 4');
    });

    test('newId 列表内唯一', () {
      final id = ServerRoute.newId(const []);
      expect(id, startsWith('rt_'));
      expect(
        ServerRoute.newId([ServerRoute(id: id, name: 'x', url: 'u')]),
        isNot(id),
      );
    });
  });

  group('buildServerUrl', () {
    test('host+port 拼 http', () {
      expect(
        buildServerUrl(host: '192.168.1.100', port: '8096'),
        'http://192.168.1.100:8096',
      );
    });

    test('useHttps 切 scheme', () {
      expect(
        buildServerUrl(host: 'emby.example.com', port: '443', useHttps: true),
        'https://emby.example.com:443',
      );
    });

    test('端口为空不拼端口段', () {
      expect(buildServerUrl(host: 'emby.example.com'), 'http://emby.example.com');
    });

    test('path 自动补前导斜杠、去尾斜杠', () {
      expect(
        buildServerUrl(host: '1.2.3.4', port: '8096', path: 'emby/'),
        'http://1.2.3.4:8096/emby',
      );
      expect(
        buildServerUrl(host: '1.2.3.4', port: '8096', path: '/emby'),
        'http://1.2.3.4:8096/emby',
      );
    });

    test('非法 host 返回 null', () {
      expect(buildServerUrl(host: ''), isNull);
      expect(buildServerUrl(host: 'http://x'), isNull);
      expect(buildServerUrl(host: 'a b'), isNull);
    });

    test('host 两端空格 trim', () {
      expect(
        buildServerUrl(host: '  1.2.3.4  ', port: '8096'),
        'http://1.2.3.4:8096',
      );
    });
  });

  group('parseServerUrl（buildServerUrl 逆运算）', () {
    test('http 带端口', () {
      final r = parseServerUrl('http://192.168.1.100:8096');
      expect(r, isNotNull);
      expect(r!.host, '192.168.1.100');
      expect(r.port, '8096');
      expect(r.path, '');
      expect(r.useHttps, false);
    });

    test('https + path', () {
      final r = parseServerUrl('https://emby.example.com:8920/emby');
      expect(r!.host, 'emby.example.com');
      expect(r.port, '8920');
      expect(r.path, 'emby');
      expect(r.useHttps, true);
    });

    test('无 scheme 按 http；无端口 port 为空', () {
      final r = parseServerUrl('emby.example.com');
      expect(r!.host, 'emby.example.com');
      expect(r.port, '');
      expect(r.useHttps, false);
    });

    test('尾斜杠去除', () {
      expect(parseServerUrl('http://1.2.3.4:8096/emby/')!.path, 'emby');
    });

    test('非法输入返回 null', () {
      expect(parseServerUrl(''), isNull);
      expect(parseServerUrl('a b'), isNull);
      expect(parseServerUrl('ftp://x'), isNull);
      expect(parseServerUrl('http://:8096'), isNull);
      expect(parseServerUrl('http://x:abc'), isNull);
    });

    test('往返一致：build → parse → build', () {
      final url = buildServerUrl(
        host: '1.2.3.4',
        port: '8096',
        path: 'emby',
        useHttps: true,
      )!;
      final r = parseServerUrl(url)!;
      expect(
        buildServerUrl(
          host: r.host,
          port: r.port,
          path: r.path,
          useHttps: r.useHttps,
        ),
        url,
      );
    });
  });
}

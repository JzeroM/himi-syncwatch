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
      expect(
          buildServerUrl(host: 'emby.example.com'), 'http://emby.example.com');
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

    test('裸 IPv6 自动补方括号', () {
      expect(
        buildServerUrl(host: '2408:85a3::8a2e:370:7334', port: '8096'),
        'http://[2408:85a3::8a2e:370:7334]:8096',
      );
    });

    test('已带方括号的 IPv6 不重复添加', () {
      expect(
        buildServerUrl(host: '[2408:85a3::8a2e:370:7334]', port: '8096'),
        'http://[2408:85a3::8a2e:370:7334]:8096',
      );
    });

    test('IPv6 + HTTPS + path', () {
      expect(
        buildServerUrl(
          host: '2408:85a3::8a2e:370:7334',
          port: '8920',
          path: 'emby',
          useHttps: true,
        ),
        'https://[2408:85a3::8a2e:370:7334]:8920/emby',
      );
    });

    test('IPv6 zone id 编码为 %25', () {
      expect(
        buildServerUrl(host: 'fe80::1%eth0', port: '8096'),
        'http://[fe80::1%25eth0]:8096',
      );
      expect(
        buildServerUrl(host: 'fe80::1%25eth0', port: '8096'),
        'http://[fe80::1%25eth0]:8096',
      );
    });

    test('非法 IPv6 / 方括号 / 端口返回 null', () {
      expect(buildServerUrl(host: '[::1'), isNull);
      expect(buildServerUrl(host: '::1]'), isNull);
      expect(buildServerUrl(host: '[foo:bar]'), isNull);
      expect(buildServerUrl(host: '1.2.3.4', port: '0'), isNull);
      expect(buildServerUrl(host: '1.2.3.4', port: '65536'), isNull);
      expect(buildServerUrl(host: '1.2.3.4', port: 'abc'), isNull);
    });
  });

  group('looksLikeFullServerUrl', () {
    test('带 scheme / path / 端口的完整地址', () {
      expect(looksLikeFullServerUrl('https://[2408::1]:8920/emby'), isTrue);
      expect(looksLikeFullServerUrl('http://emby.example.com'), isTrue);
      expect(looksLikeFullServerUrl('emby.example.com:8096'), isTrue);
      expect(looksLikeFullServerUrl('emby.example.com/emby'), isTrue);
      expect(looksLikeFullServerUrl('[2408::1]:8096'), isTrue);
    });

    test('纯 host / 纯 IPv6 不触发拆分', () {
      expect(looksLikeFullServerUrl('emby.example.com'), isFalse);
      expect(looksLikeFullServerUrl('192.168.1.10'), isFalse);
      expect(looksLikeFullServerUrl('[2408::1]'), isFalse);
      expect(looksLikeFullServerUrl('2408::1'), isFalse);
      expect(looksLikeFullServerUrl('emby.example.com:abc'), isFalse);
      expect(looksLikeFullServerUrl(''), isFalse);
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

    test('IPv6 带端口', () {
      final r = parseServerUrl('http://[2408:85a3::8a2e:370:7334]:8920');
      expect(r, isNotNull);
      expect(r!.host, '2408:85a3::8a2e:370:7334');
      expect(r.port, '8920');
      expect(r.path, '');
      expect(r.useHttps, false);
    });

    test('IPv6 无端口', () {
      final r = parseServerUrl('http://[2408::1]');
      expect(r!.host, '2408::1');
      expect(r.port, '');
      expect(r.path, '');
    });

    test('IPv6 + https + path + 显式 443', () {
      final r = parseServerUrl('https://[2408::1]:443/emby');
      expect(r!.host, '2408::1');
      expect(r.port, '443');
      expect(r.path, 'emby');
      expect(r.useHttps, true);
    });

    test('IPv6 zone id %25 解码为 %', () {
      final r = parseServerUrl('http://[fe80::1%25eth0]:8096');
      expect(r!.host, 'fe80::1%eth0');
      expect(r.port, '8096');
    });

    test('非法 IPv6 / 方括号 / 端口返回 null', () {
      expect(parseServerUrl('http://2408:85a3::1:8096'), isNull);
      expect(parseServerUrl('http://[::1'), isNull);
      expect(parseServerUrl('http://[]:8096'), isNull);
      expect(parseServerUrl('http://[::1]x'), isNull);
      expect(parseServerUrl('http://[::1]:0'), isNull);
      expect(parseServerUrl('http://[::1]:65536'), isNull);
      expect(parseServerUrl('http://[::1]:'), isNull);
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

    test('IPv6 往返一致：build → parse → build', () {
      final url = buildServerUrl(
        host: '2408:85a3::8a2e:370:7334',
        port: '8920',
        path: 'emby',
        useHttps: true,
      )!;
      final r = parseServerUrl(url)!;
      expect(r.host, '2408:85a3::8a2e:370:7334');
      expect(r.port, '8920');
      expect(r.path, 'emby');
      expect(r.useHttps, true);
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

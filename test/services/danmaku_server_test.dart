import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_server.dart';

/// P5：多弹幕服务器（模型 / 迁移 / 选择 / 备份）。
///
/// 设计约束：
/// - 老配置只有 `danmakuApiUrl`，升级必须自动迁移成一条服务器；
/// - 旧字段保留（降级回旧版本不丢地址）；
/// - 解析失败（存档损坏）不能崩，回退空列表；
/// - 「生效服务器」= 启用且优先级最小。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('1. 模型往返', () {
    test('1.1 toJson/fromJson 保留全部字段', () {
      const s = DanmakuServer(
        id: 'a',
        name: '家里',
        baseUrl: 'http://192.168.1.10:9321/TOKEN',
        type: 'custom',
        token: 'tk',
        enabled: false,
        priority: 3,
      );
      final back = DanmakuServer.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back, s);
    });

    test('1.2 缺 id / name 时兜底', () {
      final s = DanmakuServer.fromJson({'baseUrl': 'http://x'});
      expect(s, isNotNull);
      expect(s!.id, isNotEmpty);
      expect(s.name, 'http://x');
      expect(s.enabled, isTrue);
    });

    test('1.3 空地址视为非法', () {
      expect(DanmakuServer.fromJson({'baseUrl': '  '}), isNull);
      expect(DanmakuServer.fromJson('oops'), isNull);
    });
  });

  group('2. 迁移与选择', () {
    test('2.1 老 danmakuApiUrl 自动迁移成一条服务器', () {
      final s = AppSettings.fromJson(
        jsonDecode(jsonEncode({'danmakuApiUrl': 'http://old:9321'}))
            as Map<String, dynamic>,
      );
      expect(s.danmakuServers, hasLength(1));
      expect(s.danmakuServers.first.baseUrl, 'http://old:9321');
      expect(s.activeDanmakuServer?.baseUrl, 'http://old:9321');
    });

    test('2.2 空配置 → 没有生效服务器', () {
      const s = AppSettings();
      expect(s.danmakuServers, isEmpty);
      expect(s.activeDanmakuServer, isNull);
    });

    test('2.3 生效服务器 = 启用且优先级最小', () {
      final json = AppSettings.encodeDanmakuServers(const [
        DanmakuServer(id: 'b', name: 'B', baseUrl: 'http://b', priority: 1),
        DanmakuServer(id: 'a', name: 'A', baseUrl: 'http://a', priority: 0),
        DanmakuServer(
            id: 'c', name: 'C', baseUrl: 'http://c', priority: 2, enabled: false),
        DanmakuServer(
            id: 'd', name: 'D', baseUrl: 'http://d', priority: -1, enabled: false),
      ]);
      final s = AppSettings().copyWith(danmakuServersJson: json);
      expect(s.activeDanmakuServer?.baseUrl, 'http://a');
    });

    test('2.4 全部停用 → 回退老字段', () {
      final json = AppSettings.encodeDanmakuServers(const [
        DanmakuServer(id: 'a', name: 'A', baseUrl: 'http://a', enabled: false),
      ]);
      final s = AppSettings()
          .copyWith(danmakuServersJson: json, danmakuApiUrl: 'http://legacy');
      expect(s.activeDanmakuServer?.baseUrl, 'http://legacy');
    });

    test('2.5 损坏的 JSON 不崩，回退迁移', () {
      final s = AppSettings()
          .copyWith(danmakuServersJson: '{not json', danmakuApiUrl: 'http://x');
      expect(s.danmakuServers, hasLength(1));
      expect(s.danmakuServers.first.baseUrl, 'http://x');
    });
  });

  group('3. 序列化往返与备份', () {
    test('3.1 AppSettings 往返保留服务器列表', () {
      final json = AppSettings.encodeDanmakuServers(const [
        DanmakuServer(id: 'a', name: 'A', baseUrl: 'http://a', priority: 0),
        DanmakuServer(id: 'b', name: 'B', baseUrl: 'http://b', priority: 1),
      ]);
      final s = AppSettings().copyWith(danmakuServersJson: json);
      final round = AppSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(round.danmakuServers, hasLength(2));
      expect(round.danmakuServers.first.baseUrl, 'http://a');
    });

    test('3.2 备份白名单包含服务器列表', () {
      final b = read('lib/services/backup/backup_service.dart');
      expect(b, contains("'servers': settings.danmakuServersJson"));
      expect(b, contains("danmakuServersJson: danmaku?['servers']"));
    });
  });

  group('5. P2 多源回退', () {
    test('5.1 单服务器匹配抽成独立方法', () {
      final p = read('lib/screens/player/player_screen.dart');
      expect(p, contains('_loadDanmakuFromClient({'));
      expect(p, contains('return found;'));
    });

    test('5.2 并发搜索所有启用服务器，严格优先级仲裁（694 M4）', () {
      final p = read('lib/screens/player/player_screen.dart');
      expect(p, contains('.where((e) => e.enabled)'));
      expect(p, contains('..sort((a, b) => a.priority.compareTo(b.priority))'));
      expect(p, contains('runDanmakuServers<'));
      expect(p, contains('timeout: const Duration(seconds: 15)'));
      expect(p, contains('服务器无命中'));
    });

    test('5.3 起播前只要求「至少一条可用」，不是只认第一条', () {
      final p = read('lib/screens/player/player_screen.dart');
      expect(p, contains('hasUsableServer'));
      expect(p, contains('.any((e) => DandanplayClient.normalizeBaseUrl'));
    });
  });

  group('4. 接线', () {
    test('4.1 播放页用生效服务器而不是裸字段', () {
      final p = read('lib/screens/player/player_screen.dart');
      expect(p, contains('activeDanmakuServer'));
    });

    test('4.2 设置页可增删/启停服务器', () {
      final ui = read('lib/screens/settings/danmaku_config_screen.dart');
      expect(ui, contains('danmakuServerAdd'));
      expect(ui, contains('_applyServers('));
      expect(ui, contains('danmakuServerDelete-'));
    });
  });
}

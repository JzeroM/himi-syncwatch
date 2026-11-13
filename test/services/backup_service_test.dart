import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/backup/backup_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/fake_secure_storage.dart';
import '../helpers/test_fakes.dart';

/// 可在构造时注入初始状态的设置通知器（`state` 是 protected 成员）。
class _SeededSettingsNotifier extends SettingsNotifier {
  _SeededSettingsNotifier({
    FlutterSecureStorage? storage,
    AppSettings initial = const AppSettings(),
  }) : super(storage: storage) {
    state = initial;
  }
}

/// 697：配置备份 / 还原。
///
/// 覆盖的核心约束：
/// 1. **只备份用户填写的配置**（服务器 / 声网 / TMDB / 弹幕 / Trakt 登录）；
/// 2. **不备份** Trakt Client ID·Secret、字幕样式、片头片尾标记、TV 配对、
///    底层引擎参数、开关与外观偏好；
/// 3. 还原是**完全替换**（先清空服务器再写入）；
/// 4. 校验失败时**不写入任何数据**（原子性）。
void main() {
  /// 一份典型会话（`EmbyServerConfig.fromJson` 可解析）。
  Map<String, dynamic> session({
    required String id,
    required String serverId,
    String url = 'http://192.168.1.7:8096',
    String name = '家里',
    String user = 'mojito',
    String token = 'tok_1',
    String userId = 'uid_1',
  }) =>
      <String, dynamic>{
        'id': id,
        'serverId': serverId,
        'serverUrl': url,
        'serverName': name,
        'username': user,
        'accessToken': token,
        'userId': userId,
      };

  AgoraConfigModel agoraConfig() =>
      const AgoraConfigModel(appId: 'agora_app', appCertificate: 'agora_cert');

  AppSettings settingsWithConfig() => const AppSettings(
        tmdbApiKey: 'tmdb_key',
        tmdbApiBase: 'https://api.tmdb.org',
        tmdbImageBase: 'https://image.tmdb.org',
        tmdbWatchRegion: 'CN',
        danmakuApiUrl: 'https://danmaku.example/api',
        danmakuBlockWords: '剧透,广告',
        traktDisabledServerIds: 'cfg_b',
      );

  /// 组装被测服务 + 各依赖（全部走内存假实现，不触平台通道）。
  ({
    BackupService service,
    FakeEmbyAuthService auth,
    SettingsNotifier settings,
    AgoraConfigNotifier agora,
    TraktTokenStore trakt,
    FakeSecureStorage storage,
  }) build({
    List<String> serverIds = const [],
    Map<String, Map<String, dynamic>> sessions = const {},
    AppSettings? settings,
    AgoraConfigModel? agora,
    TraktTokens? tokens,
    String? selectedServerId,
    List<String> serverOrder = const [],
  }) {
    final storage = FakeSecureStorage();
    final auth = FakeEmbyAuthService(
      serverIds: serverIds,
      sessions: sessions,
    )
      ..selectedServerId = selectedServerId
      ..serverOrder = serverOrder;
    final settingsNotifier = _SeededSettingsNotifier(
      storage: storage,
      initial: settings ?? const AppSettings(),
    );
    final agoraNotifier = AgoraConfigNotifier(storage: storage);
    if (agora != null) {
      // `save` 同步置 state（写盘是 fake storage），无需 await。
      unawaited(agoraNotifier.save(agora));
    }
    final traktStore = TraktTokenStore(storage: storage);
    if (tokens != null) {
      unawaited(traktStore.writeTokens(tokens));
    }
    return (
      service: BackupService(
        authService: auth,
        settings: settingsNotifier,
        agora: agoraNotifier,
        traktTokens: traktStore,
        appVersionLoader: () async => '1.6.8+688',
      ),
      auth: auth,
      settings: settingsNotifier,
      agora: agoraNotifier,
      trakt: traktStore,
      storage: storage,
    );
  }

  group('导出（只含用户填写的配置）', () {
    test('包含服务器 / 声网 / TMDB / 弹幕 / Trakt 登录', () async {
      final env = build(
        serverIds: ['srv_1'],
        sessions: {
          'srv_1': session(id: 'cfg_1', serverId: 'srv_1'),
        },
        selectedServerId: 'cfg_1',
        serverOrder: ['cfg_1'],
        settings: settingsWithConfig(),
        agora: agoraConfig(),
        tokens: TraktTokens(
          accessToken: 'trakt_access',
          refreshToken: 'trakt_refresh',
          tokenType: 'Bearer',
          expiresAt: DateTime.utc(2030),
          createdAt: DateTime.utc(2026),
        ),
      );

      final backup = await env.service.buildBackup();

      expect(backup['app'], 'himi_syncwatch');
      expect(backup['version'], 1);
      expect(backup['createdAt'], isA<String>());

      final data = backup['data']! as Map<String, Object?>;

      // Emby 服务器（含 token）
      final servers = data['embyServers']! as List;
      expect(servers, hasLength(1));
      final first = servers.first as Map<String, Object?>;
      expect(first['serverUrl'], 'http://192.168.1.7:8096');
      expect(first['username'], 'mojito');
      expect(first['accessToken'], 'tok_1');
      expect(first['userId'], 'uid_1');
      expect(data['selectedServerId'], 'cfg_1');
      expect(data['serverOrder'], ['cfg_1']);

      // 声网
      final agora = data['agora']! as Map<String, Object?>;
      expect(agora['appId'], 'agora_app');
      expect(agora['appCertificate'], 'agora_cert');

      // TMDB
      final tmdb = data['tmdb']! as Map<String, Object?>;
      expect(tmdb['apiKey'], 'tmdb_key');
      expect(tmdb['apiBase'], 'https://api.tmdb.org');
      expect(tmdb['imageBase'], 'https://image.tmdb.org');
      expect(tmdb['watchRegion'], 'CN');

      // 弹幕（含屏蔽词）
      final danmaku = data['danmaku']! as Map<String, Object?>;
      expect(danmaku['apiUrl'], 'https://danmaku.example/api');
      expect(danmaku['blockWords'], '剧透,广告');

      // Trakt 登录态 + 用户配置
      final trakt = data['trakt']! as Map<String, Object?>;
      expect(trakt['disabledServerIds'], 'cfg_b');
      final token = trakt['token']! as Map<String, Object?>;
      expect(token['access_token'], 'trakt_access');
      expect(token['refresh_token'], 'trakt_refresh');
    });

    test('不含 Trakt Client ID / Secret', () async {
      final env = build(settings: settingsWithConfig());
      final text = jsonEncode(await env.service.buildBackup());
      expect(text.contains('client_id'), isFalse);
      expect(text.contains('client_secret'), isFalse);
      expect(text.contains('clientId'), isFalse);
      expect(text.contains('clientSecret'), isFalse);
    });

    test('不含字幕样式 / 片头片尾标记 / TV 配对', () async {
      final env = build(settings: settingsWithConfig());
      final text = jsonEncode(await env.service.buildBackup());
      expect(text.contains('subtitleStyles'), isFalse);
      expect(text.contains('himi_subtitle_styles'), isFalse);
      expect(text.contains('manualSegments'), isFalse);
      expect(text.contains('himi_manual_segments'), isFalse);
      expect(text.contains('paired_tv'), isFalse);
      expect(text.contains('pairedTv'), isFalse);
    });

    test('不含底层引擎参数', () async {
      final env = build(
        settings: const AppSettings(
          decodeMode: 'sw',
          videoOutput: 'surfaceView',
          mpvVideoOutput: 'gpu',
          mpvRenderer: 'gpu-next',
          renderCompatMode: true,
          videoDecoderNoImage: true,
          videoDecoderLowLatency: true,
          renderDepth8: true,
          hdrGlWorkaround: true,
          avsyncAudioAdaptive: true,
        ),
      );
      final text = jsonEncode(await env.service.buildBackup());
      for (final field in const [
        'decodeMode',
        'videoOutput',
        'mpvVideoOutput',
        'mpvRenderer',
        'renderCompatMode',
        'videoDecoderNoImage',
        'videoDecoderLowLatency',
        'renderDepth8',
        'hdrGlWorkaround',
        'avsyncAudioAdaptive',
        'mdkBufferMinMs',
        'mdkBufferMaxMs',
      ]) {
        expect(text.contains('"$field"'), isFalse, reason: '不应备份 $field');
      }
    });

    test('不含开关 / 外观 / 设备相关字段', () async {
      final env = build(
        settings: const AppSettings(
          tvMode: true,
          glassUi: false,
          homeCarousel: false,
          danmakuDefaultOn: false,
          skipIntroOutroEnabled: false,
          showNetworkSpeed: true,
          themeColor: 0xFF8B5CF6,
          appIcon: 'dark',
          eglFaultSeen: true,
          skipUpdateVersion: '9.9.9',
        ),
      );
      final text = jsonEncode(await env.service.buildBackup());
      for (final field in const [
        'tvMode',
        'glassUi',
        'homeCarousel',
        'danmakuDefaultOn',
        'skipIntroOutroEnabled',
        'showNetworkSpeed',
        'themeColor',
        'appIcon',
        'eglFaultSeen',
        'skipUpdateVersion',
      ]) {
        expect(text.contains('"$field"'), isFalse, reason: '不应备份 $field');
      }
    });

    test('备用线路与播放开关一并备份/还原', () async {
      final env = build(
        serverIds: ['srv_1'],
        sessions: {
          'srv_1': {
            ...session(id: 'cfg_1', serverId: 'srv_1'),
            'routes': [
              {'id': 'r1', 'name': '备用', 'url': 'https://backup.example', 'isReverseProxy': true},
            ],
            'activeRouteUrl': 'https://backup.example',
            'autoFailover': false,
            'strmDirectPlay': true,
          },
        },
      );

      final backup = await env.service.buildBackup();
      final exported = backup['data']! as Map;
      final first = (exported['embyServers'] as List).first as Map;
      expect(first['activeRouteUrl'], 'https://backup.example');
      expect(first['autoFailover'], isFalse);
      expect(first['strmDirectPlay'], isTrue);
      expect((first['routes'] as List).first['url'], 'https://backup.example');

      // 还原后再导出一次应完全一致（往返无损）
      final result = await env.service.restore(backup);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.servers.first.activeRouteUrl, 'https://backup.example');
      expect(result.servers.first.autoFailover, isFalse);
      expect(result.servers.first.strmDirectPlay, isTrue);
      expect(result.servers.first.routes.first.url, 'https://backup.example');
    });

    test('无服务器 / 无声网 / 无 Trakt 登录时字段为空但不报错', () async {
      final env = build();
      final data = (await env.service.buildBackup())['data']! as Map;
      expect(data['embyServers'], isEmpty);
      expect(data['agora'], isNull);
      expect((data['trakt']! as Map)['token'], isNull);
    });

    test('多服务器全部导出', () async {
      final env = build(
        serverIds: ['srv_1', 'srv_2'],
        sessions: {
          'srv_1': session(id: 'cfg_1', serverId: 'srv_1', name: '家里'),
          'srv_2': session(
            id: 'cfg_2',
            serverId: 'srv_2',
            name: '公司',
            url: 'https://emby.example.com',
          ),
        },
      );
      final data = (await env.service.buildBackup())['data']! as Map;
      final servers = data['embyServers'] as List;
      expect(servers, hasLength(2));
      expect((servers[1] as Map)['serverName'], '公司');
    });
  });

  group('校验（失败不写入）', () {
    test('错误 app 标识被拒绝', () {
      final env = build();
      final v = env.service.validate({
        'app': 'other_app',
        'version': 1,
        'data': <String, Object?>{},
      });
      expect(v.ok, isFalse);
      expect(v.error, contains('HIMI'));
    });

    test('过高的格式版本被拒绝', () {
      final env = build();
      final v = env.service.validate({
        'app': 'himi_syncwatch',
        'version': 99,
        'data': <String, Object?>{},
      });
      expect(v.ok, isFalse);
      expect(v.error, contains('版本'));
    });

    test('缺少 data 字段被拒绝', () {
      final env = build();
      final v = env.service.validate({
        'app': 'himi_syncwatch',
        'version': 1,
      });
      expect(v.ok, isFalse);
      expect(v.error, contains('data'));
    });

    test('非 JSON 文本被拒绝', () {
      final env = build();
      expect(env.service.validateText('not json').ok, isFalse);
      expect(env.service.validateText('[]').ok, isFalse);
    });

    test('校验通过时回传备份时间 / 版本 / 服务器数', () {
      final env = build();
      final v = env.service.validate({
        'app': 'himi_syncwatch',
        'version': 1,
        'createdAt': '2026-11-13T04:00:00.000Z',
        'appVersion': '1.6.7+687',
        'data': {
          'embyServers': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
      });
      expect(v.ok, isTrue);
      expect(v.createdAt, DateTime.utc(2026, 11, 13, 4));
      expect(v.appVersion, '1.6.7+687');
      expect(v.serverCount, 2);
    });

    test('校验失败时 restore 不写入任何数据（原子性）', () async {
      final env = build(
        serverIds: ['srv_keep'],
        sessions: {'srv_keep': session(id: 'cfg_keep', serverId: 'srv_keep')},
        settings: const AppSettings(tmdbApiKey: 'keep_key'),
      );

      final result = await env.service.restore({
        'app': 'other_app',
        'version': 1,
        'data': {
          'embyServers': [session(id: 'cfg_x', serverId: 'srv_x')],
        },
      });

      expect(result.ok, isFalse);
      // 服务器没被清空、也没被写入
      expect(env.auth.deleteAllSessionsCalls, 0);
      expect(env.auth.savedSessions, isEmpty);
      // 设置没被改动
      expect(env.settings.snapshot.tmdbApiKey, 'keep_key');
    });
  });

  group('还原（完全替换）', () {
    Map<String, Object?> backupJson({
      List<Map<String, dynamic>>? servers,
      String? selectedServerId,
      List<String>? serverOrder,
      Map<String, Object?>? agora,
      Map<String, Object?>? tmdb,
      Map<String, Object?>? danmaku,
      Map<String, Object?>? trakt,
    }) =>
        {
          'app': 'himi_syncwatch',
          'version': 1,
          'createdAt': '2026-11-13T04:00:00.000Z',
          'appVersion': '1.6.7+687',
          'data': <String, Object?>{
            'embyServers': servers ??
                [
                  session(id: 'cfg_new', serverId: 'srv_new', token: 'tok_new'),
                ],
            'selectedServerId': selectedServerId ?? 'cfg_new',
            'serverOrder': serverOrder ?? ['cfg_new'],
            if (agora != null) 'agora': agora,
            if (tmdb != null) 'tmdb': tmdb,
            if (danmaku != null) 'danmaku': danmaku,
            if (trakt != null) 'trakt': trakt,
          },
        };

    test('清空旧服务器后写入备份里的服务器', () async {
      final env = build(
        serverIds: ['srv_old'],
        sessions: {'srv_old': session(id: 'cfg_old', serverId: 'srv_old')},
        selectedServerId: 'cfg_old',
      );

      final result = await env.service.restore(backupJson());

      expect(result.ok, isTrue, reason: result.error);
      expect(env.auth.deleteAllSessionsCalls, 1, reason: '必须先清空旧会话');
      expect(env.auth.savedSessions, hasLength(1));
      expect(env.auth.savedSessions.first['serverId'], 'srv_new');
      expect(env.auth.savedSessions.first['accessToken'], 'tok_new');
      // 当前服务器 / 顺序也覆盖
      expect(env.auth.selectedServerId, 'cfg_new');
      expect(env.auth.serverOrder, ['cfg_new']);
      // 结果里带回服务器列表（供 UI 刷新 provider）
      expect(result.servers, hasLength(1));
      expect(result.servers.first.id, 'cfg_new');
      expect(result.selectedServerId, 'cfg_new');
    });

    test('多服务器按备份顺序写入', () async {
      final env = build();
      final result = await env.service.restore(backupJson(
        servers: [
          session(id: 'cfg_a', serverId: 'srv_a', name: 'A'),
          session(id: 'cfg_b', serverId: 'srv_b', name: 'B'),
          session(id: 'cfg_c', serverId: 'srv_c', name: 'C'),
        ],
        selectedServerId: 'cfg_b',
        serverOrder: ['cfg_c', 'cfg_a', 'cfg_b'],
      ));

      expect(result.ok, isTrue, reason: result.error);
      expect(env.auth.savedSessions.map((s) => s['serverId']),
          ['srv_a', 'srv_b', 'srv_c']);
      expect(result.servers.map((s) => s.id), ['cfg_a', 'cfg_b', 'cfg_c']);
      expect(env.auth.selectedServerId, 'cfg_b');
      expect(env.auth.serverOrder, ['cfg_c', 'cfg_a', 'cfg_b']);
      expect(result.restored.first, contains('3'));
    });

    test('覆盖声网配置', () async {
      final env = build(agora: agoraConfig());
      await env.service.restore(backupJson(
        agora: {'appId': 'new_app', 'appCertificate': 'new_cert'},
      ));

      expect(env.agora.snapshot?.appId, 'new_app');
      expect(env.agora.snapshot?.appCertificate, 'new_cert');
    });

    test('覆盖 TMDB / 弹幕字段（含屏蔽词）', () async {
      final env = build(settings: const AppSettings(tmdbApiKey: 'old'));
      await env.service.restore(backupJson(
        tmdb: {
          'apiKey': 'new_key',
          'apiBase': 'https://api.new',
          'imageBase': 'https://img.new',
          'watchRegion': 'US',
        },
        danmaku: {
          'apiUrl': 'https://dm.new/api',
          'blockWords': '新词1,新词2',
        },
      ));

      final s = env.settings.snapshot;
      expect(s.tmdbApiKey, 'new_key');
      expect(s.tmdbApiBase, 'https://api.new');
      expect(s.tmdbImageBase, 'https://img.new');
      expect(s.tmdbWatchRegion, 'US');
      expect(s.danmakuApiUrl, 'https://dm.new/api');
      expect(s.danmakuBlockWords, '新词1,新词2');
    });

    test('覆盖 Trakt 登录态与禁用服务器列表', () async {
      final env = build();
      await env.service.restore(backupJson(
        trakt: {
          'token': {
            'access_token': 'restored_access',
            'refresh_token': 'restored_refresh',
            'token_type': 'Bearer',
            'expires_at': '2030-01-01T00:00:00.000Z',
            'created_at': '2026-01-01T00:00:00.000Z',
          },
          'disabledServerIds': 'cfg_b,cfg_c',
        },
      ));

      final tokens = await env.trakt.readTokens();
      expect(tokens?.accessToken, 'restored_access');
      expect(tokens?.refreshToken, 'restored_refresh');
      expect(env.settings.snapshot.traktDisabledServerIds, 'cfg_b,cfg_c');
    });

    test('备份缺某个分组时保持现有配置不变', () async {
      final env = build(
        settings: const AppSettings(
          tmdbApiKey: 'keep_key',
          danmakuBlockWords: 'keep_words',
        ),
      );
      await env.service.restore(backupJson());

      expect(env.settings.snapshot.tmdbApiKey, 'keep_key');
      expect(env.settings.snapshot.danmakuBlockWords, 'keep_words');
    });

    test('还原不触碰底层引擎参数', () async {
      final env = build(
        settings: const AppSettings(
          decodeMode: 'sw',
          mpvVideoOutput: 'gpu',
          renderDepth8: true,
          hdrGlWorkaround: true,
        ),
      );
      await env.service.restore(backupJson());

      final s = env.settings.snapshot;
      expect(s.decodeMode, 'sw');
      expect(s.mpvVideoOutput, 'gpu');
      expect(s.renderDepth8, isTrue);
      expect(s.hdrGlWorkaround, isTrue);
    });

    test('空服务器列表也能还原（清空后不写）', () async {
      final env = build(
        serverIds: ['srv_old'],
        sessions: {'srv_old': session(id: 'cfg_old', serverId: 'srv_old')},
      );
      final result = await env.service.restore(backupJson(servers: []));

      expect(result.ok, isTrue, reason: result.error);
      expect(env.auth.deleteAllSessionsCalls, 1);
      expect(env.auth.savedSessions, isEmpty);
      expect(result.servers, isEmpty);
    });
  });

  group('文件读写', () {
    test('exportTo 写出可再次解析的 JSON', () async {
      final dir = await Directory.systemTemp.createTemp('himi_backup_test');
      addTearDown(() => dir.delete(recursive: true));
      final env = build(settings: settingsWithConfig());

      final file = await env.service.exportTo('${dir.path}/my-backup');
      expect(file.path, endsWith('my-backup.json'));
      expect(await file.exists(), isTrue);

      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['app'], 'himi_syncwatch');
      expect(env.service.validate(decoded.cast<String, Object?>()).ok, isTrue);
    });

    test('exportToFile 用默认文件名', () async {
      final dir = await Directory.systemTemp.createTemp('himi_backup_test');
      addTearDown(() => dir.delete(recursive: true));
      final env = build();

      final file = await env.service.exportToFile(directory: dir.path);
      expect(file.path, contains('himi-backup-'));
      expect(file.path, endsWith('.json'));
    });

    test('restoreFromFile 读文件还原', () async {
      final dir = await Directory.systemTemp.createTemp('himi_backup_test');
      addTearDown(() => dir.delete(recursive: true));
      final env = build(settings: const AppSettings(tmdbApiKey: 'old'));

      final file = File('${dir.path}/b.json');
      await file.writeAsString(jsonEncode({
        'app': 'himi_syncwatch',
        'version': 1,
        'data': {
          'embyServers': <Object?>[],
          'tmdb': {'apiKey': 'from_file'},
        },
      }));

      final result = await env.service.restoreFromFile(file);
      expect(result.ok, isTrue, reason: result.error);
      expect(env.settings.snapshot.tmdbApiKey, 'from_file');
    });

    test('restoreFromFile 文件不存在时返回失败而不抛', () async {
      final env = build();
      final result =
          await env.service.restoreFromFile(File('/no/such/backup.json'));
      expect(result.ok, isFalse);
      expect(result.error, contains('读取备份文件失败'));
    });

    test('建议文件名含日期且以 .json 结尾', () {
      expect(
        BackupService.suggestedFileName(DateTime(2026, 11, 13, 9, 5)),
        'himi-backup-20261113-0905.json',
      );
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 697：配置备份与还原。
///
/// ## 备份什么（**只含用户填写的配置项**）
///
/// - **Emby 服务器**：地址 / 用户名 / token / userId / 名称（全部服务器）
/// - **声网**：App ID + 证书
/// - **TMDB**：API Key / API 地址 / 图片地址 / 观看区域
/// - **弹幕**：API 地址 / 屏蔽词
/// - **Trakt**：登录 token + 禁用的服务器列表
///
/// ## 不备份什么
///
/// | 类别 | 原因 |
/// |---|---|
/// | Trakt client_id / secret | 开发者凭据，非用户配置 |
/// | 字幕样式 / 片头片尾标记 | 本次明确排除 |
/// | TV 配对信息 | 设备绑定，换设备无效 |
/// | 底层引擎参数（解码/HDR/渲染器） | **设备相关**，跨设备还原会黑屏 |
/// | 开关类 / 外观偏好 | 使用偏好，重设成本低 |
/// | 设备相关（eglFaultSeen 等） | 只对原设备有意义 |
///
/// ## 还原策略
///
/// **完全替换**：先清空现有 Emby 服务器，再写入备份里的全部服务器；
/// 其余配置直接覆盖。还原后**立即生效，无需重启**（不涉及引擎参数）。
class BackupService {
  BackupService({
    required EmbyAuthService authService,
    required SettingsNotifier settings,
    required AgoraConfigNotifier agora,
    required TraktTokenStore traktTokens,
    Future<String> Function()? appVersionLoader,
  })  : _auth = authService,
        _settings = settings,
        _agora = agora,
        _trakt = traktTokens,
        _appVersionLoader = appVersionLoader;

  final EmbyAuthService _auth;
  final SettingsNotifier _settings;
  final AgoraConfigNotifier _agora;
  final TraktTokenStore _trakt;

  /// 版本号读取（测试可注入，避免触碰平台通道）。
  final Future<String> Function()? _appVersionLoader;

  /// 备份格式标识（校验用，防误导入其它 JSON）。
  static const appTag = 'himi_syncwatch';

  /// 当前备份格式版本。
  static const formatVersion = 1;

  /// 从 Riverpod 容器构造（UI 层用）。
  static BackupService fromRef(WidgetRef ref) => BackupService(
        authService: ref.read(embyAuthServiceProvider),
        settings: ref.read(settingsProvider.notifier),
        agora: ref.read(agoraConfigProvider.notifier),
        traktTokens: ref.read(traktTokenStoreProvider),
      );

  // ── 导出 ────────────────────────────────────────────────────

  /// 当前应用版本（`1.6.8+688` 形式）；读不到时为空串。
  ///
  /// 【为什么用 package_info 而不是 `String.fromEnvironment`】
  /// `FLUTTER_BUILD_NAME` 只在 `--dart-define` 时注入，常规构建里恒为空，
  /// 备份文件就丢了版本信息（排查时看不出是哪个版本导出的）。
  Future<String> _appVersion() async {
    final loader = _appVersionLoader;
    if (loader != null) return loader();
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isEmpty) return '';
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  /// 构建备份 JSON（不写文件）。
  Future<Map<String, Object?>> buildBackup() async {
    final settings = _settings.snapshot;
    final agora = _agora.snapshot;

    // Emby 服务器：逐条读会话
    final serverIds = await _auth.listServerIds();
    final servers = <Map<String, Object?>>[];
    for (final id in serverIds) {
      final session = await _auth.loadSession(id);
      if (session == null) continue;
      servers.add(<String, Object?>{
        'id': session['id'] ?? id,
        'serverId': session['serverId'] ?? '',
        'serverUrl': session['serverUrl'] ?? '',
        'serverName': session['serverName'] ?? '',
        'username': session['username'] ?? '',
        'userId': session['userId'] ?? '',
        'accessToken': session['accessToken'] ?? '',
        // 用户自己填的备用线路 / 播放开关，同属「填写项」，一并带走。
        'routes': session['routes'] ?? const <Object?>[],
        'activeRouteUrl': session['activeRouteUrl'],
        'autoFailover': session['autoFailover'] ?? true,
        'strmDirectPlay': session['strmDirectPlay'] ?? false,
      });
    }

    final traktTokens = await _trakt.readTokens();

    return <String, Object?>{
      'app': appTag,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': await _appVersion(),
      'data': <String, Object?>{
        'embyServers': servers,
        'selectedServerId': await _auth.loadSelectedServerId() ?? '',
        'serverOrder': await _auth.loadServerOrder(),
        'agora': agora == null
            ? null
            : <String, Object?>{
                'appId': agora.appId,
                'appCertificate': agora.appCertificate,
              },
        'tmdb': <String, Object?>{
          'apiKey': settings.tmdbApiKey,
          'apiBase': settings.tmdbApiBase,
          'imageBase': settings.tmdbImageBase,
          'watchRegion': settings.tmdbWatchRegion,
        },
        'danmaku': <String, Object?>{
          'apiUrl': settings.danmakuApiUrl,
          'blockWords': settings.danmakuBlockWords,
        },
        'trakt': <String, Object?>{
          'token': traktTokens?.toJson(),
          'disabledServerIds': settings.traktDisabledServerIds,
        },
      },
    };
  }

  /// 建议的备份文件名（形如 `himi-backup-20261113-1200.json`）。
  static String suggestedFileName([DateTime? now]) {
    final t = (now ?? DateTime.now());
    String two(int v) => v.toString().padLeft(2, '0');
    return 'himi-backup-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}.json';
  }

  /// 导出到指定路径（UI 层 file_picker「另存为」拿到路径后调用）。
  Future<File> exportTo(String path) async {
    final json = await buildBackup();
    final target = path.toLowerCase().endsWith('.json') ? path : '$path.json';
    final file = File(target);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );
    LogService().log('Backup', '已导出备份: ${file.path}');
    return file;
  }

  /// 导出到文件。
  ///
  /// [directory] 为空时用临时目录（UI 层通过 file_picker 另存）。
  Future<File> exportToFile({String? directory}) async {
    final dir = directory ?? Directory.systemTemp.path;
    return exportTo('$dir/${suggestedFileName()}');
  }

  // ── 校验 ────────────────────────────────────────────────────

  /// 解析 JSON 文本并校验（**不写入任何数据**）。
  BackupValidation validateText(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return const BackupValidation.fail('备份文件不是有效的 JSON');
    }
    if (decoded is! Map) {
      return const BackupValidation.fail('备份文件不是有效的 JSON 对象');
    }
    return validate(decoded.cast<String, Object?>());
  }

  /// 校验备份结构（**不写入任何数据**）。
  BackupValidation validate(Map<String, Object?> json) {
    if (json['app'] != appTag) {
      return const BackupValidation.fail('不是 HIMI 的备份文件');
    }
    final version = json['version'];
    if (version is! int || version > formatVersion) {
      return const BackupValidation.fail('备份格式版本不支持（请升级应用）');
    }
    final data = json['data'];
    if (data is! Map) {
      return const BackupValidation.fail('备份文件缺少 data 字段');
    }
    final servers = data['embyServers'];
    final count = servers is List ? servers.length : 0;
    return BackupValidation.ok(
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      appVersion: json['appVersion'] as String?,
      serverCount: count,
    );
  }

  // ── 还原 ────────────────────────────────────────────────────

  /// 还原（先校验，通过后**完全替换**写入）。
  Future<BackupRestoreResult> restore(Map<String, Object?> json) async {
    final v = validate(json);
    if (!v.ok) {
      return BackupRestoreResult.fail(v.error ?? '备份文件无效');
    }

    final data = json['data'] as Map;
    final restored = <String>[];

    try {
      // ── 1. Emby 服务器：**完全替换** ──
      //
      // 先清空全部旧会话，再写入备份里的服务器——避免「备份之后新增的
      // 服务器」残留，保证还原后与备份完全一致（整机迁移语义）。
      final servers = (data['embyServers'] as List?) ?? const [];
      await _auth.deleteAllSessions();
      final restoredConfigs = <EmbyServerConfig>[];
      for (final raw in servers) {
        if (raw is! Map) continue;
        final m = raw.cast<String, Object?>();
        final serverId = (m['serverId'] as String?) ?? '';
        final id = (m['id'] as String?) ?? serverId;
        if (serverId.isEmpty && id.isEmpty) continue;
        final routes = (m['routes'] as List?)
                ?.whereType<Map>()
                .map((r) => r.cast<String, dynamic>())
                .toList() ??
            const <Map<String, dynamic>>[];
        final activeRouteUrl = m['activeRouteUrl'] as String?;
        final autoFailover = (m['autoFailover'] as bool?) ?? true;
        final strmDirectPlay = (m['strmDirectPlay'] as bool?) ?? false;
        await _auth.saveSession(
          id: id,
          serverId: serverId,
          serverUrl: (m['serverUrl'] as String?) ?? '',
          serverName: (m['serverName'] as String?) ?? '',
          username: (m['username'] as String?) ?? '',
          userId: (m['userId'] as String?) ?? '',
          accessToken: (m['accessToken'] as String?) ?? '',
          routes: routes,
          activeRouteUrl: activeRouteUrl,
          autoFailover: autoFailover,
          strmDirectPlay: strmDirectPlay,
        );
        // 用落盘内容重建配置对象，供 UI 立即刷新（避免再读一遍存储）。
        restoredConfigs.add(EmbyServerConfig.fromJson(<String, dynamic>{
          ...m.cast<String, dynamic>(),
          'id': id,
          'serverId': serverId,
          'routes': routes,
          'activeRouteUrl': activeRouteUrl,
          'autoFailover': autoFailover,
          'strmDirectPlay': strmDirectPlay,
        }));
      }
      if (restoredConfigs.isNotEmpty) {
        restored.add('Emby 服务器（${restoredConfigs.length} 个）');
      }

      final selected = data['selectedServerId'] as String? ?? '';
      if (selected.isNotEmpty) {
        await _auth.saveSelectedServerId(selected);
      }
      final order = data['serverOrder'];
      if (order is List) {
        await _auth.saveServerOrder(order.cast<String>());
      }

      // ── 2. 声网 ──
      final agora = data['agora'];
      if (agora is Map) {
        final appId = agora['appId'] as String? ?? '';
        if (appId.isNotEmpty) {
          await _agora.save(AgoraConfigModel(
            appId: appId,
            appCertificate: agora['appCertificate'] as String? ?? '',
          ));
          restored.add('声网配置');
        }
      }

      // ── 3. TMDB / 弹幕 / Trakt 设置字段 ──
      //
      // 只写备份里**实际存在**的字段：备份缺某个分组时保持当前值不变
      // （不把用户现有配置清成 null）。
      final tmdb = (data['tmdb'] as Map?)?.cast<String, Object?>();
      final danmaku = (data['danmaku'] as Map?)?.cast<String, Object?>();
      final trakt = (data['trakt'] as Map?)?.cast<String, Object?>();

      final hasSettings = tmdb != null || danmaku != null || trakt != null;
      if (hasSettings) {
        await _settings.update(
          tmdbApiKey: tmdb?['apiKey'] as String?,
          tmdbApiBase: tmdb?['apiBase'] as String?,
          tmdbImageBase: tmdb?['imageBase'] as String?,
          tmdbWatchRegion: tmdb?['watchRegion'] as String?,
          danmakuApiUrl: danmaku?['apiUrl'] as String?,
          danmakuBlockWords: danmaku?['blockWords'] as String?,
          traktDisabledServerIds: trakt?['disabledServerIds'] as String?,
        );
      }
      if (tmdb != null) restored.add('TMDB');
      if (danmaku != null) restored.add('弹幕');
      if (trakt != null) restored.add('Trakt 设置');

      // ── 4. Trakt token（登录态）──
      final tokenRaw = trakt?['token'];
      if (tokenRaw is Map) {
        final tokens = TraktTokens.fromJson(tokenRaw.cast<String, dynamic>());
        await _trakt.writeTokens(tokens);
        restored.add('Trakt 登录');
      }

      LogService().log('Backup', '还原完成: ${restored.join('、')}');
      return BackupRestoreResult.ok(
        restored: restored,
        servers: restoredConfigs,
        selectedServerId: selected.isEmpty ? null : selected,
      );
    } catch (e, st) {
      LogService().log('Backup', '还原失败: $e\n$st');
      return BackupRestoreResult.fail('还原失败: $e');
    }
  }

  /// 从文件还原。
  Future<BackupRestoreResult> restoreFromFile(File file) async {
    try {
      final text = await file.readAsString();
      return await restoreFromText(text);
    } catch (e) {
      return BackupRestoreResult.fail('读取备份文件失败: $e');
    }
  }

  /// 从 JSON 文本还原（UI 层已用 [validateText] 预检过）。
  Future<BackupRestoreResult> restoreFromText(String text) async {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return BackupRestoreResult.fail('备份文件不是有效的 JSON');
    }
    if (decoded is! Map) {
      return BackupRestoreResult.fail('备份文件不是有效的 JSON 对象');
    }
    return restore(decoded.cast<String, Object?>());
  }

  /// 还原后通知 provider 刷新（**即时生效，无需重启**）。
  ///
  /// 【为什么单独一个方法】还原逻辑本身不依赖 Riverpod（便于单测）；
  /// UI 层在 `restore` 成功后调用本方法刷新 UI。
  ///
  /// 【为什么 agora 不 invalidate】`AgoraConfigNotifier.save()` 内部已把
  /// `state` 换成新配置（同一个 notifier 实例），监听方会自动重建；
  /// 再 invalidate 反而会把 state 重置成 null。
  static Future<void> refreshProviders(
    WidgetRef ref,
    BackupRestoreResult result,
  ) async {
    final servers = result.servers;
    ref.read(embyServerListProvider.notifier).setList(servers);
    final selectedId = result.selectedServerId;
    final selected = selectedId == null
        ? servers.firstOrNull
        : servers.where((s) => s.id == selectedId).firstOrNull ??
            servers.firstOrNull;
    if (selected == null) {
      ref.read(embyConfigProvider.notifier).clear();
    } else {
      ref.read(embyConfigProvider.notifier).setConfig(selected);
    }
    // Trakt：token 已落盘，但 `TraktProvider` 内存里还是旧登录态——
    // 重建 provider 并重新 init() 才能让设置页立即显示「已连接」。
    //
    // 【为什么不 await init()】init 里会做 token 刷新/取账号的网络请求，
    // 等它完成再弹「已还原」会让用户以为卡住；这里异步触发即可。
    if (result.restored.contains('Trakt 登录')) {
      ref.invalidate(traktProvider);
      unawaited(ref.read(traktProvider.notifier).init());
    }
  }
}

/// 备份校验结果。
@immutable
class BackupValidation {
  const BackupValidation.ok({
    this.createdAt,
    this.appVersion,
    this.serverCount = 0,
  })  : ok = true,
        error = null;

  const BackupValidation.fail(String message)
      : ok = false,
        error = message,
        createdAt = null,
        appVersion = null,
        serverCount = 0;

  final bool ok;
  final String? error;
  final DateTime? createdAt;
  final String? appVersion;
  final int serverCount;
}

/// 还原结果。
@immutable
class BackupRestoreResult {
  const BackupRestoreResult.ok({
    required this.restored,
    this.servers = const [],
    this.selectedServerId,
  })  : ok = true,
        error = null;

  const BackupRestoreResult.fail(String message)
      : ok = false,
        error = message,
        restored = const [],
        servers = const [],
        selectedServerId = null;

  final bool ok;
  final String? error;

  /// 已还原的配置项中文名（用于结果提示）。
  final List<String> restored;

  /// 还原后的服务器列表（按备份顺序；UI 直接 `setList` 用）。
  final List<EmbyServerConfig> servers;

  /// 备份里记录的当前服务器 id（可能不在 [servers] 里）。
  final String? selectedServerId;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/tv_sync/paired_tv_store.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_config_syncer.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_device_name.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_discovery.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_sync_server.dart';

/// 手机端「已配对 TV」状态（加载/配对成功/解除后刷新）。
class PairedTvNotifier extends StateNotifier<PairedTv?> {
  PairedTvNotifier({PairedTvStore? store})
      : _store = store ?? PairedTvStore(),
        super(null) {
    _load();
  }

  final PairedTvStore _store;

  Future<void> _load() async {
    final tv = await _store.load();
    if (mounted) state = tv;
  }

  Future<void> set(PairedTv tv) async {
    state = tv;
    await _store.save(tv);
  }

  Future<void> clear() async {
    state = null;
    await _store.clear();
  }
}

final pairedTvProvider =
    StateNotifierProvider<PairedTvNotifier, PairedTv?>((ref) {
  return PairedTvNotifier();
});

/// TV 端局域网同步常驻服务控制器。
///
/// tvMode=true 时启动 [TvSyncServer]（HTTP 配对/同步）+
/// [TvDiscoveryBroadcaster]（UDP 广播「我在」包）；关闭 tvMode 即停止。
class TvSyncController {
  TvSyncController(this._ref);

  final Ref _ref;

  TvSyncServer? _server;
  TvDiscoveryBroadcaster? _broadcaster;
  String? _deviceName;
  bool _starting = false;

  bool get isRunning => _server?.isRunning == true;

  Future<void> start() async {
    if (_starting || isRunning) return;
    _starting = true;
    try {
      final auth = _ref.read(embyAuthServiceProvider);
      final deviceId = auth.deviceId;
      final deviceName = _deviceName ??= await resolveLocalDeviceName();
      final server = TvSyncServer(
        deviceId: deviceId,
        deviceName: deviceName,
        onPairRequest: _confirmPair,
        onSync: _handleSync,
      );
      await server.start();
      _server = server;
      _broadcaster = TvDiscoveryBroadcaster(
        deviceId: deviceId,
        deviceName: deviceName,
        httpPort: server.port!,
      );
      await _broadcaster!.start();
      LogService().log(
          'TvSync', 'TV 同步服务已启动 name=$deviceName port=${server.port}');
    } catch (e) {
      LogService().log('TvSync', '启动失败: $e');
      await _server?.stop();
      _server = null;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final server = _server;
    final broadcaster = _broadcaster;
    _server = null;
    _broadcaster = null;
    await broadcaster?.stop();
    await server?.stop();
    if (server != null) LogService().log('TvSync', 'TV 同步服务已停止');
  }

  /// 手机请求配对 → 弹确认框（60s 无操作自动拒绝）。
  Future<bool> _confirmPair(String phoneName, String ip) async {
    final overlay = routerKey.currentState?.overlay;
    if (overlay == null) return false;
    try {
      final agreed = await showDialog<bool>(
        context: overlay.context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('设备配对请求'),
          content: Text('「$phoneName」（$ip）请求连接本设备并同步服务器配置。\n\n同意后该手机可向本机推送 Emby 服务器。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('同意'),
            ),
          ],
        ),
      ).timeout(const Duration(seconds: 60), onTimeout: () => false);
      LogService().log(
          'TvSync', '配对请求 phone=$phoneName ip=$ip → ${agreed == true ? '同意' : '拒绝'}');
      return agreed == true;
    } catch (e) {
      LogService().log('TvSync', '配对弹框失败: $e');
      return false;
    }
  }

  /// 同步落库：委托 [TvConfigSyncer] 按 serverId upsert；TV 端原本
  /// 一台服务器都没有时，激活第一台。
  Future<String?> _handleSync(List<EmbyServerConfig> servers) async {
    final auth = _ref.read(embyAuthServiceProvider);
    final listNotifier = _ref.read(embyServerListProvider.notifier);
    final existing =
        List<EmbyServerConfig>.of(_ref.read(embyServerListProvider));

    final result = await TvConfigSyncer(auth: auth)
        .upsert(existing: existing, incoming: servers);
    if (!result.ok) return result.error;

    listNotifier.setList(result.list);
    final activateTarget = result.activateTarget;
    if (activateTarget != null) {
      _ref.read(embyConfigProvider.notifier).setConfig(activateTarget);
      await auth.saveSelectedServerId(activateTarget.id);
    }
    LogService().log('TvSync', '已同步 ${result.syncedCount} 个服务器'
        '${activateTarget != null ? '（首台已激活）' : ''}');
    return null;
  }
}

final tvSyncProvider = Provider<TvSyncController>((ref) {
  final controller = TvSyncController(ref);
  ref.listen(
    settingsProvider.select((s) => s.tvMode),
    (prev, next) {
      if (next) {
        unawaited(controller.start());
      } else {
        unawaited(controller.stop());
      }
    },
  );
  // main.dart 在 runApp 前已 load 设置 → 首次读取即正确
  if (ref.read(settingsProvider).tvMode) {
    unawaited(controller.start());
  }
  ref.onDispose(controller.stop);
  return controller;
});

/// 手机端局域网 TV 发现监听（进服务器页/面板时启动）。
class TvDiscoveryNotifier extends StateNotifier<Map<String, TvDeviceInfo>> {
  TvDiscoveryNotifier() : super(const {});

  TvDiscoveryListener? _listener;

  bool get isRunning => _listener?.isRunning == true;

  Future<void> start() async {
    if (isRunning) {
      _listener!.sendQuery();
      return;
    }
    final listener = TvDiscoveryListener();
    _listener = listener;
    listener.devicesStream.listen((devices) {
      if (mounted) state = devices;
    });
    try {
      await listener.start();
      listener.sendQuery();
    } catch (e) {
      LogService().log('TvSync', '发现监听启动失败: $e');
    }
  }

  Future<void> stop() async {
    final listener = _listener;
    _listener = null;
    await listener?.stop();
    listener?.dispose();
    if (mounted) state = const {};
  }

  @override
  void dispose() {
    final listener = _listener;
    _listener = null;
    listener?.stop();
    listener?.dispose();
    super.dispose();
  }
}

final tvDiscoveryProvider =
    StateNotifierProvider.autoDispose<TvDiscoveryNotifier, Map<String, TvDeviceInfo>>(
        (ref) => TvDiscoveryNotifier());

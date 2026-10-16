import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_device_name.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_sync_client.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/sheet_bottom_safe_area.dart';
import 'package:himi_syncwatch/widgets/swipe_reveal_action.dart';

/// 打开「TV 设备」发现/配对底部面板。
Future<void> showTvDeviceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const TvDeviceSheet(),
  );
}

/// 局域网 TV 设备列表：点击设备 → TV 弹窗配对 → 成功后卡片出现电视图标。
class TvDeviceSheet extends ConsumerStatefulWidget {
  const TvDeviceSheet({super.key});

  @override
  ConsumerState<TvDeviceSheet> createState() => _TvDeviceSheetState();
}

class _TvDeviceSheetState extends ConsumerState<TvDeviceSheet> {
  final _client = TvSyncClient();

  /// 正在等待 TV 确认配对的设备 id（按钮转圈用）。
  String? _pairingId;

  /// 正在推送全部服务器的设备 id。
  String? _pushingId;

  @override
  void initState() {
    super.initState();
    // build 里 ref.watch 会保持 provider 存活；microtask 在首帧后启动监听
    Future.microtask(() {
      if (mounted) ref.read(tvDiscoveryProvider.notifier).start();
    });
  }

  Future<void> _pair(TvDeviceInfo device) async {
    if (_pairingId != null) return;
    setState(() => _pairingId = device.deviceId);
    try {
      final phoneName = await resolveLocalDeviceName();
      final token = await _client.pair(device.baseUrl, phoneName: phoneName);
      if (!mounted) return;
      await ref.read(pairedTvProvider.notifier).set(
            PairedTv.fromDevice(device, token),
          );
      if (!mounted) return;
      showAppToast(context, '已配对「${device.name}」');
    } on TvSyncException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '配对失败：无法连接设备');
    } finally {
      if (mounted) setState(() => _pairingId = null);
    }
  }

  /// 取消配对：清除本地配对记录（TV 端不记录配对方，无需服务端调用）。
  Future<void> _unpair(TvDeviceInfo device) async {
    await ref.read(pairedTvProvider.notifier).clear();
    if (mounted) showAppToast(context, '已取消配对「${device.name}」');
  }

  Future<void> _pushAll(TvDeviceInfo device) async {
    if (_pushingId != null) return;
    final paired = ref.read(pairedTvProvider);
    if (paired == null || paired.deviceId != device.deviceId) {
      showAppToast(context, '请先配对该设备');
      return;
    }
    final servers = ref.read(embyServerListProvider);
    if (servers.isEmpty) {
      showAppToast(context, '没有可同步的服务器');
      return;
    }
    setState(() => _pushingId = device.deviceId);
    try {
      await _client.pushServers(
        paired.baseUrl,
        token: paired.token,
        servers: servers,
      );
      if (!mounted) return;
      showAppToast(context, '已同步 ${servers.length} 个服务器到「${device.name}」');
    } on TvSyncException catch (e) {
      if (!mounted) return;
      if (e.message.contains('配对已失效')) {
        await ref.read(pairedTvProvider.notifier).clear();
      }
      showAppToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '同步失败：无法连接设备');
    } finally {
      if (mounted) setState(() => _pushingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(tvDiscoveryProvider).values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final paired = ref.watch(pairedTvProvider);

    return SheetBottomSafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tv, size: 20, color: Colors.white70),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'TV 设备',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '重新搜索',
                  onPressed: () =>
                      ref.read(tvDiscoveryProvider.notifier).start(),
                ),
                IconButton(
                  key: const ValueKey('tvDeviceSheetClose'),
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '确保 TV 版 HIMI 与本机在同一局域网',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '未发现 TV 设备，搜索中…',
                    style: TextStyle(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isPaired = paired?.deviceId == device.deviceId;
                    final row = GlassContainer(
                      borderRadius: BorderRadius.circular(14),
                      tint: GlassConfig.panelTintOf(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tv,
                              size: 22,
                              color: isPaired
                                  ? Colors.greenAccent
                                  : Colors.white54,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${device.ip}:${device.httpPort}'
                                    '${isPaired ? ' · 已配对' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isPaired
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.8)
                                          : Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isPaired)
                              TextButton.icon(
                                icon: _pushingId == device.deviceId
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync, size: 16),
                                label: const Text('同步全部'),
                                onPressed: _pushingId == null
                                    ? () => _pushAll(device)
                                    : null,
                              ),
                            const SizedBox(width: 4),
                            FilledButton.tonal(
                              onPressed: _pairingId == null && !isPaired
                                  ? () => _pair(device)
                                  : null,
                              child: _pairingId == device.deviceId
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(isPaired ? '已配对' : '配对'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!isPaired) return row;
                    return SwipeRevealAction(
                      key: ValueKey('unpair_${device.deviceId}'),
                      actionLabel: '取消配对',
                      actionIcon: Icons.link_off,
                      onAction: () => _unpair(device),
                      child: row,
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 供服务器卡片/列表判断是否展示「同步到 TV」图标按钮。
bool showServerSyncToTv(PairedTv? paired) => paired != null;

/// 推送单个服务器到已配对 TV。
Future<void> pushServerToTv(
  BuildContext context,
  WidgetRef ref,
  EmbyServerConfig server,
) async {
  final paired = ref.read(pairedTvProvider);
  if (paired == null) return;
  final client = TvSyncClient();
  try {
    await client.pushServers(
      paired.baseUrl,
      token: paired.token,
      servers: [server],
    );
    if (context.mounted) {
      showAppToast(context, '已同步到「${paired.name}」');
    }
  } on TvSyncException catch (e) {
    if (e.message.contains('配对已失效')) {
      await ref.read(pairedTvProvider.notifier).clear();
    }
    if (context.mounted) showAppToast(context, e.message);
  } catch (_) {
    if (context.mounted) showAppToast(context, '同步失败：无法连接设备');
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/trakt/trakt_sync_status_panel.dart';
import 'package:himi_syncwatch/widgets/tv/tv_confirm_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class TraktSettingsScreen extends ConsumerStatefulWidget {
  const TraktSettingsScreen({super.key});

  @override
  ConsumerState<TraktSettingsScreen> createState() =>
      _TraktSettingsScreenState();
}

class _TraktSettingsScreenState extends ConsumerState<TraktSettingsScreen> {
  Timer? _deviceTimer;

  @override
  void dispose() {
    _deviceTimer?.cancel();
    super.dispose();
  }

  void _stopDeviceTimer() {
    _deviceTimer?.cancel();
    _deviceTimer = null;
  }

  Future<void> _browserLogin() async {
    if (ref.read(traktProvider).connecting) return;
    final notifier = ref.read(traktProvider.notifier);
    final uri = await notifier.beginPkce();
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      showAppToast(context, '无法打开浏览器');
    }
  }

  Future<void> _openQrLogin() async {
    _stopDeviceTimer();
    await ref.read(traktProvider.notifier).cancelDeviceFlow();
    if (!mounted) return;
    await context.push<void>('/settings/general/trakt/qr');
  }

  Future<void> _deviceLogin() async {
    if (ref.read(traktProvider).connecting) return;
    _stopDeviceTimer();
    final notifier = ref.read(traktProvider.notifier);
    final code = await notifier.startDeviceFlow();
    if (!mounted || code == null) return;
    final interval = Duration(seconds: code.interval <= 0 ? 5 : code.interval);
    _deviceTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      final current = ref.read(traktProvider).deviceCode;
      if (current == null) {
        _stopDeviceTimer();
        return;
      }
      unawaited(notifier.pollDeviceFlow());
    });
  }

  Future<void> _openVerification(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || ok) return;
    showAppToast(context, '无法打开浏览器');
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showAppToast(context, '设备码已复制');
  }

  Future<void> _disconnect() async {
    final confirmed = await showTvConfirmDialog(
      context: context,
      title: '断开 Trakt？',
      message: '将撤销本机授权并清除本机 Trakt 登录凭据，不影响 Trakt 上已有的观看记录。',
      confirmLabel: '断开',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(traktProvider.notifier).disconnect();
    if (!mounted) return;
    showAppToast(context, '已断开 Trakt');
  }

  List<EmbyServerConfig> _servers() {
    final map = <String, EmbyServerConfig>{};
    final current = ref.watch(embyConfigProvider);
    if (current != null) map[current.id] = current;
    for (final server in ref.watch(embyServerListProvider)) {
      map[server.id] = server;
    }
    return map.values.where((e) => e.isAuthenticated).toList();
  }

  void _setServerEnabled(String id, bool enabled) {
    final settings = ref.read(settingsProvider);
    final disabled = settings.traktDisabledServerIdSet;
    if (enabled) {
      disabled.remove(id);
    } else {
      disabled.add(id);
    }
    ref.read(settingsProvider.notifier).update(
          traktDisabledServerIds: disabled.join(','),
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TraktAppState>(traktProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        showAppToast(context, next.error!);
      }
      if (previous?.deviceCode != null && next.deviceCode == null) {
        _stopDeviceTimer();
      }
    });

    final trakt = ref.watch(traktProvider);
    final settings = ref.watch(settingsProvider);
    final servers = _servers();
    final sync = trakt.syncState;

    return SettingsSubPage(
      pageKey: const ValueKey('traktSettingsPage'),
      title: 'Trakt 同步',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            '以 Trakt 为中转，在多个 Emby 服务器之间同步电影与单集的已看状态和播放进度。'
            '已看取并集；全部未看时才取最长进度。自动同步在应用启动或回到前台时执行，'
            '间隔可在下方设置。',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.5,
            ),
          ),
        ),
        const Divider(height: 1),
        if (!trakt.configured)
          const ListTile(
            leading: Icon(Icons.warning_amber, color: Colors.orangeAccent),
            title: Text('当前构建未配置 Trakt Client ID'),
            subtitle: Text('请使用注入了 TRAKT_CLIENT_ID 的正式构建'),
          ),
        if (!trakt.connected) ...[
          if (settings.tvMode && trakt.configured) ...[
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: _openQrLogin,
              child: ListTile(
                key: const ValueKey('traktQrLogin'),
                leading: const Icon(Icons.qr_code),
                title: const Text('扫码配置'),
                subtitle: const Text('手机扫码后输入设备码，电视端自动完成 Trakt 授权'),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white54,
                ),
                onTap: _openQrLogin,
              ),
            ),
            const Divider(height: 1),
          ],
          if ((Platform.isAndroid || Platform.isIOS) && !settings.tvMode)
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: _browserLogin,
              child: ListTile(
                key: const ValueKey('traktBrowserLogin'),
                leading: const Icon(Icons.open_in_browser),
                title: const Text('浏览器登录'),
                subtitle: const Text('使用 Trakt 安全授权页，PKCE 校验后返回 HIMI'),
                enabled: trakt.configured && !trakt.connecting,
                onTap: _browserLogin,
              ),
            ),
          if ((Platform.isAndroid || Platform.isIOS) && !settings.tvMode)
            const Divider(height: 1),
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: _deviceLogin,
            child: ListTile(
              key: const ValueKey('traktDeviceLogin'),
              leading: const Icon(Icons.tv_outlined),
              title: const Text('设备码登录'),
              subtitle: const Text('TV / Windows 推荐：在任意设备输入短码完成授权'),
              enabled: trakt.configured && !trakt.connecting,
              onTap: _deviceLogin,
            ),
          ),
          if (trakt.connecting) ...[
            const Divider(height: 1),
            const ListTile(
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('正在连接 Trakt…'),
            ),
          ],
          if (trakt.deviceCode != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('在浏览器中输入设备码'),
              subtitle: Text(
                trakt.deviceCode!.userCode,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyCode(trakt.deviceCode!.userCode),
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => _openVerification(trakt.deviceCode!.verificationUrl),
              child: ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('打开授权页面'),
                subtitle: Text(trakt.deviceCode!.verificationUrl),
                onTap: () =>
                    _openVerification(trakt.deviceCode!.verificationUrl),
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => ref.read(traktProvider.notifier).cancelDeviceFlow(),
              child: ListTile(
                leading: Icon(Icons.close, color: Colors.red.shade300),
                title: const Text('取消设备授权'),
                onTap: () =>
                    ref.read(traktProvider.notifier).cancelDeviceFlow(),
              ),
            ),
          ],
          if (!trakt.connecting && trakt.deviceCode == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(
                '提示：Trakt 免费账号同时只能连接一个第三方客户端。'
                '如授权后无法同步，请先在 Trakt 设置中断开其他客户端。',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  height: 1.5,
                ),
              ),
            ),
        ],
        if (trakt.connected) ...[
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(
              trakt.account == null
                  ? 'Trakt 已连接'
                  : '@${trakt.account!.username}',
            ),
            subtitle: Text(
              trakt.account?.name.isNotEmpty == true
                  ? trakt.account!.name
                  : 'Trakt 账号',
            ),
          ),
          const Divider(height: 1),
          TraktSyncStatusPanel(
            syncState: sync,
            live: trakt.liveSync,
            syncing: trakt.syncing,
            onSync: () => ref.read(traktProvider.notifier).syncNow(),
          ),
          const Divider(height: 1),
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => ref.read(settingsProvider.notifier).update(
                  traktAutoSync: !settings.traktAutoSync,
                ),
            child: SwitchListTile(
              title: const Text('自动同步'),
              subtitle: const Text('启动或回到前台时，按设定间隔自动执行'),
              value: settings.traktAutoSync,
              onChanged: (value) => ref.read(settingsProvider.notifier).update(
                    traktAutoSync: value,
                  ),
            ),
          ),
          if (settings.traktAutoSync) ...[
            const Divider(height: 1),
            settingOptionTile(
              context: context,
              tvMode: settings.tvMode,
              title: '自动同步间隔',
              subtitle: '10–60 分钟，步进 10 分钟',
              labels: const {
                '10': '10 分钟',
                '20': '20 分钟',
                '30': '30 分钟',
                '40': '40 分钟',
                '50': '50 分钟',
                '60': '60 分钟',
              },
              value: '${settings.traktSyncIntervalMinutes}',
              onSelected: (value) => ref.read(settingsProvider.notifier).update(
                    traktSyncIntervalMinutes: int.parse(value),
                  ),
            ),
          ],
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              '参与的服务器',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          if (servers.isEmpty)
            const ListTile(
              title: Text('暂无已认证服务器'),
              subtitle: Text('请先在服务器页登录 Emby'),
            )
          else
            for (final server in servers) ...[
              settingsTvWrapRow(
                tvMode: settings.tvMode,
                onTap: () => _setServerEnabled(
                  server.id,
                  !settings.isTraktServerEnabled(server.id),
                ),
                child: SwitchListTile(
                  key: ValueKey('traktServer_${server.id}'),
                  title: Text(server.serverName),
                  subtitle: Text(server.effectiveUrl),
                  value: settings.isTraktServerEnabled(server.id),
                  onChanged: (value) => _setServerEnabled(server.id, value),
                ),
              ),
              const Divider(height: 1),
            ],
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: _disconnect,
            child: ListTile(
              key: const ValueKey('traktDisconnect'),
              leading: const Icon(Icons.logout),
              title: const Text('断开 Trakt'),
              onTap: _disconnect,
            ),
          ),
        ],
      ],
    );
  }
}

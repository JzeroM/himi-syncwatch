import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 播放器设置枢纽页：播放器配置入口 / 网速 / 弹幕配置。
///
/// 引擎专属设置（解码/音频/视频输出）在「播放器配置」tabbed 子页；
/// **引擎切换仅在播放器内**（engine_menu_panel），本页不提供切换。
class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final engines =
        PlayerEngineFactory.supportedEngines(tvMode: settings.tvMode);

    return SettingsSubPage(
      pageKey: const ValueKey('playerSettingsPage'),
      title: '播放器',
      children: [
        // ── 默认引擎（起播用；播放器内切换仅本会话）────────────
        if (engines.length > 1) ...[
          settingOptionTile(
            context: context,
            tvMode: settings.tvMode,
            title: '默认引擎',
            subtitle: _engineDesc(settings.defaultEngine),
            labels: {for (final e in engines) e.id: e.label},
            value: settings.defaultEngine,
            onSelected: (v) => notifier.update(defaultEngine: v),
          ),
          const Divider(height: 1),
        ],
        // ── 播放器配置（tabbed：MDK / media_kit / Erika）────────
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/player/engine-config'),
          child: ListTile(
            key: const ValueKey('engineConfigEntry'),
            leading: const Icon(Icons.tune),
            title: const Text('播放器配置'),
            subtitle: const Text('各引擎解码/音频/视频设置（引擎切换在播放器内）'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/player/engine-config'),
          ),
        ),
        const Divider(height: 1),
        // ── 跨引擎通用项 ─────────────────────────────────────
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () =>
              notifier.update(showNetworkSpeed: !settings.showNetworkSpeed),
          child: SwitchListTile(
            title: const Text('显示网速'),
            subtitle: const Text('播放页顶栏右侧显示真实下载速度（播放时≈视频流速度）'),
            value: settings.showNetworkSpeed,
            onChanged: (v) => notifier.update(showNetworkSpeed: v),
          ),
        ),
        const Divider(height: 1),
        // 弹幕子页入口：速度/大小/透明度在播放页显示调节面板，此处管
        // 源地址 / 行数 / 屏蔽 / 上限
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/player/danmaku'),
          child: ListTile(
            key: const ValueKey('danmakuConfigEntry'),
            leading: const Icon(Icons.comment),
            title: const Text('弹幕配置'),
            subtitle: const Text('弹幕 API 地址、行数、屏蔽与同屏上限'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/player/danmaku'),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  static String _engineDesc(String id) {
    switch (id) {
      case 'media_kit':
        return 'media_kit（libmpv，仅 Windows）';
      case 'erika':
        return 'Erika（原生位图字幕 PGS + HDR）';
      default:
        return 'MDK（默认，原生 Dolby Vision）';
    }
  }
}

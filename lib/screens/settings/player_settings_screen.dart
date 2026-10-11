import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 播放器设置枢纽页：引擎选择 / 网速 / 弹幕配置入口。
///
/// Phase 3 起引擎专属设置（解码/音视频输出等）移入 mdk|mediakit 子页；
/// 此页仅保留跨引擎通用项与子页入口。
class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    // TV 模式仅 mdk（media_kit 无 TV 验证）
    final showEnginePicker = !settings.tvMode;

    return SettingsSubPage(
      pageKey: const ValueKey('playerSettingsPage'),
      title: '播放器',
      children: [
        // ── 引擎选择（非 TV）─────────────────────────────────
        if (showEnginePicker) ...[
          settingOptionTile(
            context: context,
            tvMode: settings.tvMode,
            title: '播放引擎',
            subtitle: settings.playerEngine == 'media_kit'
                ? 'media_kit（libmpv，实验性，DV P5 不支持）'
                : 'MDK（默认，原生 DV 支持）',
            labels: const {'mdk': 'MDK', 'media_kit': 'media_kit'},
            value: settings.playerEngine,
            onSelected: (v) => notifier.update(playerEngine: v),
          ),
          const Divider(height: 1),
          // 引擎专属设置入口
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => context.push(
              settings.playerEngine == 'media_kit'
                  ? '/settings/player/mediakit'
                  : '/settings/player/mdk',
            ),
            child: ListTile(
              key: const ValueKey('engineSettingsEntry'),
              leading: const Icon(Icons.tune),
              title: Text(
                settings.playerEngine == 'media_kit'
                    ? 'media_kit 引擎设置'
                    : 'MDK 引擎设置',
              ),
              subtitle: const Text('解码方式、音视频输出等引擎专属选项'),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white54,
              ),
              onTap: () => context.push(
                settings.playerEngine == 'media_kit'
                    ? '/settings/player/mediakit'
                    : '/settings/player/mdk',
              ),
            ),
          ),
          const Divider(height: 1),
        ] else ...[
          // TV 模式：直接展示 mdk 引擎设置入口（无引擎选择）
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => context.push('/settings/player/mdk'),
            child: ListTile(
              key: const ValueKey('mdkSettingsEntry'),
              leading: const Icon(Icons.tune),
              title: const Text('MDK 引擎设置'),
              subtitle: const Text('解码方式、音视频输出等引擎专属选项'),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white54,
              ),
              onTap: () => context.push('/settings/player/mdk'),
            ),
          ),
          const Divider(height: 1),
        ],
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
}

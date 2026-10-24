import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 播放器设置枢纽页：默认播放器说明 / 播放器配置入口 / 网速 / 弹幕配置。
///
/// 引擎专属设置（解码/音频/视频输出）在「播放器配置」tabbed 子页。
/// 默认播放器为平台默认：Android/Windows 使用 MDK，iOS 使用 Erika。
/// 每次进入播放器从平台默认开始；播放页顶栏切换仅当前播放会话生效，
/// 不改变默认，剧集下一集沿用当前内核。
class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('playerSettingsPage'),
      title: '播放器',
      children: [
        // ── 默认播放器说明（静态，不提供选择器）────────────────
        ListTile(
          key: const ValueKey('defaultPlayerInfo'),
          leading: const Icon(Icons.play_circle_outline),
          title: const Text('默认播放器'),
          subtitle: const Text(
            '平台默认：Android/Windows 使用 MDK，iOS 使用 Erika。'
            '每次进入播放器从默认引擎开始；播放页切换仅当前播放，'
            '下一集沿用当前内核',
          ),
        ),
        const Divider(height: 1),
        // ── 播放器配置（tabbed：MDK / media_kit / Erika）────────
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/player/engine-config'),
          child: ListTile(
            key: const ValueKey('engineConfigEntry'),
            leading: const Icon(Icons.tune),
            title: const Text('播放器配置'),
            subtitle: const Text('各引擎解码/音频/视频设置'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/player/engine-config'),
          ),
        ),
        const Divider(height: 1),
        // ── 片头片尾配置 ─────────────────────────────────────
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/player/intro-outro'),
          child: ListTile(
            key: const ValueKey('introOutroConfigEntry'),
            leading: const Icon(Icons.skip_next),
            title: const Text('片头片尾配置'),
            subtitle: const Text('跳过提示、手动标记与自动跳过'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/player/intro-outro'),
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
}

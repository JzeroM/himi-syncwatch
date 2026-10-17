import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 播放器设置枢纽页：引擎路由说明 / 播放器配置入口 / 网速 / 弹幕配置。
///
/// 引擎专属设置（解码/音频/视频输出）在「播放器配置」tabbed 子页。
/// 引擎选择全自动路由（TV 与手机同一套规则）：SDR→MDK；HDR→设备
/// 能力评估满足 Erika 条件（Vulkan + HDR 显示）时用 Erika，否则
/// MDK 直写/HDR 透传；Windows media_kit。本页不提供手动切换。
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
        // ── 引擎自动路由说明（静态，不可切换）────────────────
        ListTile(
          key: const ValueKey('engineAutoRouteInfo'),
          leading: const Icon(Icons.account_tree),
          title: const Text('播放引擎'),
          subtitle: const Text(
              '自动路由：SDR→MDK；HDR→设备能力评估满足 Erika 条件时用 Erika，'
              '否则 MDK 直写/HDR 透传；Windows media_kit'),
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

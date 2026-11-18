import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 播放器设置枢纽页：默认播放器说明 / 播放器配置入口 / 网速 / 弹幕配置。
///
/// 引擎专属设置（解码/音频/视频输出）在「播放器配置」tabbed 子页。
/// 默认播放器为平台默认：**Android / 鸿蒙 / Windows 使用 MPV，
/// iOS 使用 Erika**（MDK 作为 TV 备选内核保留在设置里）。
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
        // 690：分组玻璃卡片——播放引擎 / 播放行为 / 弹幕
        SettingsGroupCard(
          title: '播放引擎',
          children: [
            // 694：默认播放引擎（可改，写 playerKernel）——选项/文案只写
            // **当前平台**引擎（TV：MDK / MPV；手机：MPV；iOS：Erika）。
            // 每次进入播放器从默认引擎开始；播放页切换仅当前播放，下一集
            // 沿用当前内核。
            KeyedSubtree(
              key: const ValueKey('defaultPlayerInfo'),
              child: Builder(builder: (context) {
                final engines = PlayerEngineFactory.supportedEngines(
                    tvMode: settings.tvMode);
                final names = engines.map((e) => e.label).join(' / ');
                return settingOptionTile(
                  context: context,
                  tvMode: settings.tvMode,
                  title: '默认播放器',
                  subtitle: '当前平台（$names）：每次进入播放器从默认引擎开始；'
                      '播放页切换仅当前播放，下一集沿用当前内核',
                  labels: {for (final e in engines) e.id: e.label},
                  value: PlayerEngineFactory.resolveSelectedEngine(
                          settings.playerKernel,
                          tvMode: settings.tvMode)
                      .id,
                  onSelected: (v) => notifier.update(playerKernel: v),
                );
              }),
            ),
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
          ],
        ),
        SettingsGroupCard(
          title: '播放行为',
          children: [
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
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => notifier
                  .update(showNetworkSpeed: !settings.showNetworkSpeed),
              child: SwitchListTile(
                title: const Text('显示网速'),
                subtitle: const Text('播放页顶栏右侧显示真实下载速度（播放时≈视频流速度）'),
                value: settings.showNetworkSpeed,
                onChanged: (v) => notifier.update(showNetworkSpeed: v),
              ),
            ),
          ],
        ),
        SettingsGroupCard(
          title: '弹幕',
          children: [
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => context.push('/settings/player/danmaku'),
              child: ListTile(
                key: const ValueKey('danmakuConfigEntry'),
                leading: const Icon(Icons.comment),
                title: const Text('弹幕配置'),
                subtitle: const Text('弹幕源、行数、屏蔽与样式'),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white54,
                ),
                onTap: () => context.push('/settings/player/danmaku'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

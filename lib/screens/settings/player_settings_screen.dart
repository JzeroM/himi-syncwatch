import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/danmaku_config_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 播放器设置子页：解码方式 / 立体声降混 / 音频后端 / 视频输出 / 网速 / 弹幕配置。
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
        settingOptionTile(
          context: context,
          tvMode: settings.tvMode,
          title: '解码方式',
          subtitle: decodeModeDescription(settings.decodeMode),
          labels: AppSettings.decodeModeLabels,
          value: settings.decodeMode,
          onSelected: (v) => notifier.update(decodeMode: v),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () =>
              notifier.update(stereoDownmix: !settings.stereoDownmix),
          child: SwitchListTile(
            title: const Text('立体声降混'),
            subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
            value: settings.stereoDownmix,
            onChanged: (v) => notifier.update(stereoDownmix: v),
          ),
        ),
        // AAudio/OpenSL/AudioTrack 为 Android 专属后端，其余平台固定自动
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const Divider(height: 1),
          settingOptionTile(
            context: context,
            tvMode: settings.tvMode,
            title: '音频后端',
            subtitle: audioRendererDescription(settings.audioRenderer),
            labels: AppSettings.audioRendererLabels,
            value: settings.audioRenderer,
            onSelected: (v) => notifier.update(audioRenderer: v),
          ),
          const Divider(height: 1),
          settingOptionTile(
            context: context,
            tvMode: settings.tvMode,
            title: '视频输出',
            subtitle: videoOutputDescription(settings.videoOutput),
            labels: AppSettings.videoOutputLabels,
            value: settings.videoOutput,
            onSelected: (v) => notifier.update(videoOutput: v),
          ),
        ],
        const Divider(height: 1),
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DanmakuConfigScreen(),
            ),
          ),
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DanmakuConfigScreen(),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

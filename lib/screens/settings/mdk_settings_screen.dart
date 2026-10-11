import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// mdk（fvp/libmdk）引擎专属设置页：解码方式 / 立体声降混 / 音频后端 /
/// 视频输出 / HDR 工作区。
///
/// Phase 3 起从播放器枢纽页进入；TV 模式默认引擎。
class MdkSettingsScreen extends ConsumerWidget {
  const MdkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('mdkSettingsPage'),
      title: 'MDK 引擎',
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
          onTap: () => notifier.update(stereoDownmix: !settings.stereoDownmix),
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
      ],
    );
  }
}

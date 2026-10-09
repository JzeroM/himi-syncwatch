import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 实验性设置子页：渲染兼容模式 / 播放调试面板 / 深度诊断。
class ExperimentalSettingsScreen extends ConsumerWidget {
  const ExperimentalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('experimentalSettingsPage'),
      title: '实验性',
      children: [
        // 渲染兼容模式：mdk 全局 GL 选项（rockchip 硬解渲染 /
        // SurfaceTexture 上下文），仅启动时读取注入 → 重启生效
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(renderCompatMode: !settings.renderCompatMode),
            child: SwitchListTile(
              title: const Text('渲染兼容模式（实验）'),
              subtitle: const Text(
                '启用 rockchip GL 渲染变体（yuv 采样 / SurfaceTexture 上下文）。'
                '视频全黑时尝试，修改后需重启应用生效',
              ),
              value: settings.renderCompatMode,
              onChanged: (v) => notifier.update(renderCompatMode: v),
            ),
          ),
          const Divider(height: 1),
        ],
        // 解码调优：Android 硬解器 AImageReader+YUV 采样；iOS VT 输出缩放。
        // 针对高码率/高帧率 4K 解码吞吐，全平台可开关（全局项需重启生效）。
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () =>
              notifier.update(decodeTuning: !settings.decodeTuning),
          child: SwitchListTile(
            title: const Text('解码调优（实验）'),
            subtitle: const Text(
              'Android：AImageReader 直出 + YUV 采样；iOS：VT 输出缩放。'
              '改善高码率/4K 解码吞吐；画面异常可关闭（全局项需重启生效）',
            ),
            value: settings.decodeTuning,
            onChanged: (v) => notifier.update(decodeTuning: v),
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => notifier.update(showSyncDebug: !settings.showSyncDebug),
          child: SwitchListTile(
            title: const Text('播放调试面板'),
            subtitle: const Text('实时显示播放诊断信息，可拖拽移动'),
            value: settings.showSyncDebug,
            onChanged: (v) => notifier.update(showSyncDebug: v),
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () =>
              notifier.update(deepDiagnostics: !settings.deepDiagnostics),
          child: SwitchListTile(
            title: const Text('深度诊断'),
            subtitle: const Text(
              '抓取 mdk 内部日志获取实测帧率。仅诊断卡顿时开启，可能增加少量开销',
            ),
            value: settings.deepDiagnostics,
            onChanged: (v) => notifier.update(deepDiagnostics: v),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

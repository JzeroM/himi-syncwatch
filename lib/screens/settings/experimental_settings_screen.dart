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
        // HDR 输出自适应：mdk 全局 videoout.hdr（HDR10 4K60 丢帧 A/B
        // 实验），仅启动时读取注入 → 重启生效；Android EGL 可能忽略
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(videoOutHdrAuto: !settings.videoOutHdrAuto),
            child: SwitchListTile(
              title: const Text('HDR 输出自适应（实验）'),
              subtitle: const Text(
                'mdk videoout.hdr：关闭恒 tone map 到 sRGB（默认），'
                '开启按屏幕能力启用 HDR 输出。HDR 片卡顿 A/B 对比用，'
                '修改后需重启应用生效',
              ),
              value: settings.videoOutHdrAuto,
              onChanged: (v) => notifier.update(videoOutHdrAuto: v),
            ),
          ),
          const Divider(height: 1),
        ],
        // HDR image=0 实验：AMediaCodec 解码器 image=1（AImageReader）在
        // HDR10 P010 上疑似慢路径，注入 image=0 回退旧 Surface 输出。
        // 仅 Android（AMediaCodec）；立即生效（setProperty 作用于当前
        // 解码器实例，下次起播/切集按新值重开）。
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(
                videoDecoderNoImage: !settings.videoDecoderNoImage),
            child: SwitchListTile(
              title: const Text('HDR image=0（实验）'),
              subtitle: const Text(
                '解码器 image=0：禁用 AImageReader/AHardwareBuffer 路径，'
                '回退旧 Surface/BufferQueue 输出。HDR10 4K60 丢帧 A/B '
                '对比用，修改后下次起播生效',
              ),
              value: settings.videoDecoderNoImage,
              onChanged: (v) => notifier.update(videoDecoderNoImage: v),
            ),
          ),
          const Divider(height: 1),
        ],
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

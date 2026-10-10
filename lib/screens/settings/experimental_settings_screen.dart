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
          // low_latency=1 实验（1.1.192）：AMediaCodec 解码器属性，
          // 改变硬解器内部 buffer 管理路径。10-bit P010 4K60 簇状
          // 丢帧 A/B 对比用（硬解丢帧、软解不丢）。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(
                videoDecoderLowLatency: !settings.videoDecoderLowLatency),
            child: SwitchListTile(
              title: const Text('硬解 low_latency=1（实验）'),
              subtitle: const Text(
                'AMediaCodec low_latency=1：改变硬解器 buffer 管理路径。'
                '10-bit 4K60 丢帧 A/B 对比用，修改后下次起播生效',
              ),
              value: settings.videoDecoderLowLatency,
              onChanged: (v) => notifier.update(videoDecoderLowLatency: v),
            ),
          ),
          const Divider(height: 1),
          // 8-bit 渲染表面实验（1.1.193）：EGL_SDR_DEPTH=8 强制 8-bit
          // EGL 表面（默认 10-bit RGB10A2）。Adreno 740 的 10-bit 表面
          // 跨上下文采样疑似损坏（类似 fvp#374 PowerVR/Realtek），
          // 导致 HDR10 tone map 后仍丢帧。仅 Android EGL 生效。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(renderDepth8: !settings.renderDepth8),
            child: SwitchListTile(
              title: const Text('8-bit 渲染表面（实验）'),
              subtitle: const Text(
                'EGL_SDR_DEPTH=8：强制 8-bit SDR 渲染表面。'
                '修复 HDR10 丢帧（10-bit 表面损坏），10-bit SDR 可能'
                '轻微 banding。修改后需重启应用生效',
              ),
              value: settings.renderDepth8,
              onChanged: (v) => notifier.update(renderDepth8: v),
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
          // 强制 SDR 输出实验（1.1.196）：setColorSpace(bt709) 强制
          // tone map 到 SDR。修复 HDR10 在 SDR 面板上的发白问题
          // （v1.1.191），但与 HDR 渲染夹紧实验相互独立，可单独 A/B。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(forceSdrOutput: !settings.forceSdrOutput),
            child: SwitchListTile(
              title: const Text('强制 SDR 输出（实验）'),
              subtitle: const Text(
                'setColorSpace(bt709)：强制 tone map 到 SDR，修复 HDR10 '
                '发白。关闭可隔离 HDR 夹紧实验。修改后下次起播生效',
              ),
              value: settings.forceSdrOutput,
              onChanged: (v) => notifier.update(forceSdrOutput: v),
            ),
          ),
          const Divider(height: 1),
          // HDR 渲染夹紧实验（1.1.196）：HDR 内容渲染尺寸 contain-fit
          // 到设备物理分辨率，降低 GL/Flutter 纹理负载。仅 HDR 内容
          // 生效，SDR 不受影响。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(
                renderClampHdrOnly: !settings.renderClampHdrOnly),
            child: SwitchListTile(
              title: const Text('HDR 渲染夹紧（实验）'),
              subtitle: const Text(
                'HDR 内容渲染尺寸夹紧到设备物理分辨率，降低纹理负载。'
                '仅 HDR 生效。修改后下次起播生效',
              ),
              value: settings.renderClampHdrOnly,
              onChanged: (v) => notifier.update(renderClampHdrOnly: v),
            ),
          ),
          const Divider(height: 1),
        ],
    );
  }
}

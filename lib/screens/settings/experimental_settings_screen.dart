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
          // HDR GL 渲染方案（fvp#379 workaround，1.1.198）：单一开关
          // 控制完整方案——HDR 直写降级到同载体 GL 路径 + SurfaceView
          // buffer 夹紧 + setColorSpace(bt709) tone map。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(hdrGlWorkaround: !settings.hdrGlWorkaround),
            child: SwitchListTile(
              title: const Text('HDR GL 渲染方案'),
              subtitle: const Text(
                'fvp#379：HDR 内容自动降级到 GL 渲染路径 + buffer 夹紧 + '
                'tone map。关闭则不干预（HDR 直写可能 wedge，仅 A/B）。'
                '修改后下次起播生效',
              ),
              value: settings.hdrGlWorkaround,
              onChanged: (v) => notifier.update(hdrGlWorkaround: v),
            ),
          ),
          const Divider(height: 1),
          // HDR 直通实验（本次修正）：videoout.hdr=1 且不强制
          // setColorSpace(bt709)，交还 mdk auto 协商 HDR 输出。
          // 仅在启动能力评估确认显示具备 HDR 能力时跳过强制；
          // SDR 输出设备（盒子类）无效果（仍走 bt709 tone map）。默认关。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(hdrPassthrough: !settings.hdrPassthrough),
            child: SwitchListTile(
              title: const Text('HDR 直通（实验）'),
              subtitle: const Text(
                'HDR 输出直通：videoout.hdr=1 且不强制 bt709 tone map，'
                '交还 mdk 自动协商（需显示设备支持 HDR）。默认关闭；'
                '修改后需重启应用生效',
              ),
              value: settings.hdrPassthrough,
              onChanged: (v) => notifier.update(hdrPassthrough: v),
            ),
          ),
          const Divider(height: 1),
          // 音频自适应同步（avsync.audio.adaptive）：视频落后时放慢
          // 音频追赶，mdk 0.37.0 引入（此前注入但 mdk 无此选项为空
          // 操作，升级后首次真正生效）。SDR 卡顿 A/B 第一手段。默认关。
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(
                avsyncAudioAdaptive: !settings.avsyncAudioAdaptive),
            child: SwitchListTile(
              title: const Text('音频自适应同步（实验）'),
              subtitle: const Text(
                'avsync.audio.adaptive=1：视频落后时放慢音频追赶。'
                '改善卡顿（音调轻微变化）。默认关闭；修改后需重启应用生效',
              ),
              value: settings.avsyncAudioAdaptive,
              onChanged: (v) => notifier.update(avsyncAudioAdaptive: v),
            ),
          ),
          const Divider(height: 1),
        ],
    );
  }
}

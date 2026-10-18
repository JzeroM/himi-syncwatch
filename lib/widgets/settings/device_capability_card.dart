import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/device_profile_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/egl_fault_detector.dart';
import 'package:himi_syncwatch/services/hdr_output_policy.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 「播放器配置」页顶部设备能力卡片：展示启动评估结果（显示 HDR /
/// GL-EGL / Vulkan / 硬解 / DV）+ 当前自动路由策略预览，并提供
/// 「重新评估」（重跑原生探针）与「清除兼容标记」（复位 EGL 故障
/// 持久标记后重评）两个动作。TV 与手机同一份展示。
class DeviceCapabilityCard extends ConsumerWidget {
  const DeviceCapabilityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(deviceProfileProvider);
    final settings = ref.watch(settingsProvider);
    final eglMarked = settings.eglFaultSeen;

    return Padding(
      key: const ValueKey('deviceCapabilityCard'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: GlassContainer(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  '设备能力评估',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  profile.probed ? '已评估' : '未评估',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!profile.probed)
              const Text(
                '未执行原生评估（非 Android 或通道不可用）——'
                '路由按历史默认行为执行。',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              )
            else ...[
              _CapRow(
                label: '运行环境',
                value: [
                  if (profile.android)
                    '${profile.is64Bit ? "64" : "32"} 位 · ${profile.abi}',
                  if (profile.soc != null && profile.soc!.isNotEmpty)
                    profile.soc!,
                  if (profile.sdkInt != null) 'API ${profile.sdkInt}',
                ].join(' · '),
              ),
              _CapRow(label: '显示 HDR', value: profile.display.display),
              _CapRow(
                label: 'GL / EGL',
                value: profile.gl.display +
                    (eglMarked && profile.gl.eglOk ? ' · 兼容标记已置位' : ''),
              ),
              _CapRow(
                label: 'Vulkan',
                value: profile.vulkanOk
                    ? '${profile.vulkanDisplay}'
                    : '无（真 HDR10 不可用）',
              ),
              _CapRow(
                label: '硬解',
                value: 'HEVC HDR10 ${profile.hevcHdr10 ? "支持" : "不支持"}'
                    '${profile.dvDecode != null ? " · DV ${profile.dvDecode!.summary}" : ""}',
              ),
              _CapRow(
                label: '输出策略',
                value: _policyPreview(ref, eglMarked),
              ),
              if (profile.error != null)
                _CapRow(label: '探针错误', value: profile.error!),
            ],
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('deviceCapabilityReprobe'),
                  onPressed: () => _reprobe(context, ref),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新评估', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  key: const ValueKey('deviceCapabilityClearMark'),
                  onPressed: () => _clearCompatMark(context, ref),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('清除兼容标记', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 策略预览：当前自动路由/输出决策将如何落地（只读展示）。
  String _policyPreview(WidgetRef ref, bool eglMarked) {
    final profile = ref.read(deviceProfileProvider);
    final renderable = profile.erikaRenderable(defaultTargetPlatform);
    final hdrOk = profile.erikaHdrCapable(defaultTargetPlatform);
    final dvColor = PlayerScreen.dvOutputColorSpace(
      platform: defaultTargetPlatform,
      display: profile.display,
    );
    final dvDesc = dvColor == AdapterColorSpace.bt2100PQ
        ? 'HDR10'
        : 'SDR tone map';
    // 非 DV HDR 走 MDK 时的输出色彩策略（按最佳载体 SurfaceView 预览）
    final mdkHdr = HdrOutputPolicy.resolve(
      platform: defaultTargetPlatform,
      enabled: ref.read(settingsProvider).hdrGlWorkaround,
      isHdr10: true,
      isHlg: false,
      display: profile.display,
      channelCanCarryHdr: true,
    );
    final mdkHdrDesc = switch (mdkHdr) {
      AdapterColorSpace.bt2100PQ => 'HDR10 透传',
      AdapterColorSpace.bt2100hlg => 'HLG 透传',
      AdapterColorSpace.bt709 => 'SDR tone map',
      _ => '默认',
    };
    final parts = <String>[
      'DV→MDK（LLDV：$dvDesc）',
      if (!renderable)
        'HDR→MDK（$mdkHdrDesc）'
      else if (hdrOk)
        'HDR→Erika（真 HDR10）'
      else
        'HDR→Erika（SDR 回退）',
      profile.tenBitGlBroken ? '10-bit SDR→直写（GL 纹理不可用）' : '10-bit SDR→GL',
      if (eglMarked || profile.eglBroken(eglFaultSeen: false)) 'EGL 兼容标记已置位',
    ];
    return parts.join('；');
  }

  Future<void> _reprobe(BuildContext context, WidgetRef ref) async {
    final profile = await DeviceProfileService.instance.probe();
    ref.read(deviceProfileProvider.notifier).state = profile;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('设备能力评估已更新：${profile.summary}')),
    );
  }

  Future<void> _clearCompatMark(BuildContext context, WidgetRef ref) async {
    eglFaultDetector.reset();
    await ref.read(settingsProvider.notifier).update(eglFaultSeen: false);
    final profile = await DeviceProfileService.instance.probe();
    ref.read(deviceProfileProvider.notifier).state = profile;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(profile.eglBroken(eglFaultSeen: false)
            ? '兼容标记已清除；重评仍判定 EGL 不可用，已保留直写策略'
            : '兼容标记已清除，重评通过；下次起播恢复 GL 渲染路径'),
      ),
    );
  }
}

class _CapRow extends StatelessWidget {
  const _CapRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

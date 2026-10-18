import 'package:flutter/foundation.dart' show TargetPlatform;

import 'device_profile.dart';
import 'player/player_adapter.dart';

/// 非 DV HDR 内容在 MDK 引擎下的输出色彩空间策略（纯函数，便于单测）。
///
/// 背景：本仓全局 `videoout.hdr` 恒 0（见 [buildFvpOptions] 文档头），
/// 逐内容 HDR 输出完全由 `Player.set(ColorSpace)` 控制。DV 内容走
/// [PlayerScreen.dvOutputColorSpace]；本类补齐**非 DV HDR（HDR10/HLG）**
/// 的缺口——此前除"SDR 屏强制 tone map"外一律不调 `set`，导致 HDR10
/// 片源即便在 HDR 屏上也只是 mdk 默认行为，拿不到稳定的真 HDR 输出。
///
/// 生效范围：仅 Android。非 DV HDR 在 iOS 走 Erika、Windows 走 media_kit
/// （见 `PlayerEngineFactory.resolveEngineForContent`），只有 Android 在
/// Vulkan/GLES3 双无时才把 HDR 交给 MDK，故此处只处理 Android，其余
/// 平台返回 null（不设置，保持既有行为）。
///
/// 规则（[enabled] = Android `hdrGlWorkaround` 开关，关=不干预 A/B 基线）：
/// - 内容 HDR10 且显示支持 HDR10 且载体能载 HDR → `bt2100PQ`（真 HDR10）
/// - 内容 HLG 且显示支持 HLG 且载体能载 HDR → `bt2100hlg`（真 HLG）
/// - 其余 HDR（SDR 屏 / 载体为 Flutter 纹理）→ `bt709`（显式 SDR tone map，
///   避免 mdk auto 对 SDR 面板发白 + 丢帧 + 纹理黑屏，mdk-sdk#361/fvp#379）
/// - 非 HDR → null（不设置）
class HdrOutputPolicy {
  const HdrOutputPolicy._();

  /// 解析非 DV HDR 的输出色彩空间；null = 不调用 `setColorSpace`。
  ///
  /// [channelCanCarryHdr]：当前输出载体能否携带 HDR（SurfaceView/直写/
  /// tunnel → true；Flutter 纹理恒 SDR → false）。
  static AdapterColorSpace? resolve({
    required TargetPlatform platform,
    required bool enabled,
    required bool isHdr10,
    required bool isHlg,
    required DisplayCapabilities display,
    required bool channelCanCarryHdr,
  }) {
    if (platform != TargetPlatform.android) return null;
    if (!enabled) return null;
    if (!isHdr10 && !isHlg) return null;
    if (isHdr10 && display.supportsHdr10 && channelCanCarryHdr) {
      return AdapterColorSpace.bt2100PQ;
    }
    if (isHlg && display.supportsHlg && channelCanCarryHdr) {
      return AdapterColorSpace.bt2100hlg;
    }
    return AdapterColorSpace.bt709;
  }
}

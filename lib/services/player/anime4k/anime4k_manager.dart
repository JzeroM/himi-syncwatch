import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'anime4k_catalog.dart';

/// 守卫拦截原因（状态行/调试面板直接显示）。
enum Anime4KSkipReason {
  none(''),
  off('关'),
  highRes('已跳过：4K 内容（可在设置强开）'),
  hdr('已跳过：HDR 内容（可在设置强开）');

  const Anime4KSkipReason(this.label);
  final String label;
}

/// 694 S1：Anime4K 三重守卫（借鉴 NeoPlayer QualityGuard，代码自写）。
///
/// - **4K+ 视频默认跳过**（防过热；设置 `anime4kIn4k` 可强开）
/// - **HDR/DV 内容默认跳过**（tone map 管线与着色器顺序未经实测；
///   设置 `anime4kOnHdr` 可强开）
/// - 关闭状态直接短路
class Anime4KGuard {
  Anime4KGuard._();

  static Anime4KSkipReason check({
    required bool enabled,
    required Anime4KMode mode,
    required int videoWidth,
    required int videoHeight,
    required bool isHdrContent,
    required bool in4k,
    required bool onHdr,
  }) {
    if (!enabled || mode == Anime4KMode.off) return Anime4KSkipReason.off;
    final longEdge =
        videoWidth > videoHeight ? videoWidth : videoHeight;
    if (longEdge >= 3840 && !in4k) return Anime4KSkipReason.highRes;
    if (isHdrContent && !onHdr) return Anime4KSkipReason.hdr;
    return Anime4KSkipReason.none;
  }
}

/// 着色器资产解包：Flutter assets → 真实文件路径（mpv `glsl-shaders`
/// 只吃文件路径）。
class Anime4KAssets {
  Anime4KAssets._();

  /// 资产版本（换着色器时递增，触发重新解包）。
  static const String assetVersion = 'v1';

  static Future<String> Function()? debugDirOverride;

  /// 确保着色器已解包，返回目录路径（幂等）。
  static Future<String> ensureUnpacked({
    AssetBundle? bundle,
  }) async {
    final AssetBundle b = bundle ?? rootBundle;
    final String dirPath;
    if (debugDirOverride != null) {
      dirPath = await debugDirOverride!();
    } else {
      final base = await getApplicationSupportDirectory();
      dirPath = '${base.path}${Platform.pathSeparator}anime4k$assetVersion';
    }
    final dir = Directory(dirPath);
    final marker = File('${dirPath}${Platform.pathSeparator}.ok');
    if (await marker.exists()) return dirPath;
    await dir.create(recursive: true);
    for (final name in Anime4KShaderCatalog.allFileNames) {
      final data = await b.load('third_party/anime4k/glsl/$name');
      await File('${dirPath}${Platform.pathSeparator}$name')
          .writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    await marker.writeAsString('ok');
    return dirPath;
  }
}

/// apply 结果（状态行/调试面板直接消费）。
class Anime4KApplyResult {
  const Anime4KApplyResult({
    required this.statusLabel,
    this.applied = false,
    this.error,
  });

  final String statusLabel;
  final bool applied;
  final String? error;
}

/// 694 S2：管线——把「模式 × 质量」落到 mpv `glsl-shaders`。
class Anime4KPipeline {
  Anime4KPipeline._();

  /// 着色器链的 mpv 列表分隔符（unix `:` / windows `;`）。
  static String get listSeparator => Platform.isWindows ? ';' : ':';

  /// 判断一条 mpv 日志是否为着色器编译/加载失败。
  static bool isShaderError(String e) {
    final s = e.toLowerCase();
    return s.contains('shader') ||
        s.contains('glsl') ||
        s.contains('compile') ||
        s.contains('spir-v') ||
        s.contains('spirv') ||
        s.contains('glslang');
  }

  /// 应用当前配置：守卫 → 解包 → 写属性 → **回读校验**；关/拦截时清空属性。
  ///
  /// [setProperty] 由调用方注入（安卓/鸿蒙走 himi_mpv 会话，Windows 走
  /// Qt `setProperty` 管道命令）。
  /// [readProperty] 实时回读 mpv 属性（区分「写入成功」vs「mpv 真接受并
  /// 挂载」——否则着色器静默失败也报 ✓）。[recentErrors] 最近 mpv 错误日志
  /// （抓着色器编译失败）。两者缺一时退回乐观 ✓。
  static Future<Anime4KApplyResult> apply({
    required bool enabled,
    required Anime4KMode mode,
    required Anime4KQuality quality,
    required bool in4k,
    required bool onHdr,
    required int videoWidth,
    required int videoHeight,
    required bool isHdrContent,
    required Future<void> Function(String name, String value) setProperty,
    Future<String?> Function(String name)? readProperty,
    List<String> Function()? recentErrors,
    AssetBundle? bundle,
  }) async {
    final skip = Anime4KGuard.check(
      enabled: enabled,
      mode: mode,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      isHdrContent: isHdrContent,
      in4k: in4k,
      onHdr: onHdr,
    );
    if (skip != Anime4KSkipReason.none) {
      // 拦截/关闭一律清空（换内容后不残留着色器）。
      await setProperty('glsl-shaders', '');
      return Anime4KApplyResult(statusLabel: skip.label);
    }
    try {
      final dir = await Anime4KAssets.ensureUnpacked(bundle: bundle);
      final chain = Anime4KShaderCatalog.chain(mode, quality);
      final value = [
        for (final f in chain) '$dir${Platform.pathSeparator}$f',
      ].join(listSeparator);
      await setProperty('glsl-shaders', value);
      final base = '${mode.label} / ${quality.label}（${chain.length} 链）';

      // ── 回读校验（区分「写入成功」vs「真挂载」vs「编译失败」）──
      if (readProperty == null) {
        // 无回读通路（未接）：退回乐观 ✓。
        return Anime4KApplyResult(statusLabel: '✓ $base', applied: true);
      }
      String? mounted;
      try {
        mounted = await readProperty('glsl-shaders');
      } catch (_) {
        mounted = null;
      }
      if (mounted == null) {
        // 无法回读（引擎不支持 / round-trip 超时）→ 乐观 ✓（已写入，未校验）。
        return Anime4KApplyResult(statusLabel: '✓ $base（已写入）', applied: true);
      }
      if (mounted.trim().isEmpty) {
        // 回读为空 = mpv 明确未接受 glsl-shaders → 写入未生效。
        return Anime4KApplyResult(
          statusLabel: '⚠ $base 写入未生效',
          error: 'glsl-shaders 回读为空（mpv 未接受）',
        );
      }
      // 着色器已挂载，但可能编译失败（挂了没编译过 → 不渲染）。
      final errs = recentErrors?.call() ?? const <String>[];
      String? shaderErr;
      for (final e in errs.reversed) {
        if (isShaderError(e)) {
          shaderErr = e;
          break;
        }
      }
      if (shaderErr != null) {
        return Anime4KApplyResult(
          statusLabel: '⚠ $base 编译失败',
          error: shaderErr,
        );
      }
      return Anime4KApplyResult(
        statusLabel: '✓ $base 已挂载渲染中',
        applied: true,
      );
    } catch (e) {
      // 失败：清空 + 状态行带原因（真机截图即诊断）。
      try {
        await setProperty('glsl-shaders', '');
      } catch (_) {}
      return Anime4KApplyResult(
        statusLabel: '✗ 失败：$e',
        error: '$e',
      );
    }
  }
}

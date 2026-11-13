import 'package:himi_syncwatch/services/debug/debug_metrics.dart';
import 'package:himi_syncwatch/services/player/mpv_player_adapter.dart';

/// 697：播放调试面板的指标采集器。
///
/// ## 职责边界
///
/// **只负责「读数据 + 组装」，不碰 UI**。四端（Flutter / Android /
/// HarmonyOS / Windows Qt）都消费同一份 [DebugMetrics]，保证看到的是
/// 同一组数字——避免「Flutter 面板显示 HDR 直出，原生面板显示 SDR」
/// 这种互相矛盾的情况。
///
/// ## HDR / DV 排查的关键三元组
///
/// 排查 HDR/DV 问题必须同时看三层，缺一层就无法定位：
///
/// | 层 | 数据源 | 回答什么问题 |
/// |---|---|---|
/// | **输入** | `video-params` | 片源是什么？（色域/transfer/峰值/DV Profile） |
/// | **决策** | `dvContent` / `hdrContent` | 我们把它识别成什么了？ |
/// | **输出** | `target-prim`/`target-trc`/`tone-mapping`/`current-vo` | 最终怎么渲染的？ |
///
/// 典型故障：
/// - 输入 pq、决策 HDR、输出 auto → **HDR 开关没生效**
/// - 输入 pq、决策 HDR、输出 pq，但画面发灰 → **tone-mapping 算法不对**
/// - 输入 DV P5、决策 HDR（非 DV）→ **DV 未识别，P5 会偏色**
class DebugMetricsCollector {
  DebugMetricsCollector({required MpvPlayerAdapter adapter}) : _adapter = adapter;

  final MpvPlayerAdapter _adapter;

  /// mpv 实时属性清单（只读这些，避免无谓 IPC）。
  static const _mpvPropertyNames = <String>[
    // 输入色彩（片源真相）
    'video-params',
    // 输出色彩（实际渲染）
    'target-prim',
    'target-trc',
    'target-peak',
    'tone-mapping',
    'tone-mapping-mode',
    'hdr-compute-peak',
    // 渲染管线
    'current-vo',
    'gpu-api',
    'gpu-context',
    'd3d11-output-format',
    'd3d11-output-csp',
    // 性能
    'estimated-vf-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'hwdec-current',
    'video-format',
    'audio-codec-name',
    'audio-params',
  ];

  /// 采集一次完整指标。
  Future<DebugMetrics> collect({
    required String playbackState,
    required int positionMs,
    required int durationMs,
    required int bufferedMs,
    required double speed,
  }) async {
    final props = await _adapter.readDebugProperties(_mpvPropertyNames);
    final videoParams = VideoColorInfo.tryParse(props['video-params']);

    return DebugMetrics([
      _playbackGroup(
        playbackState: playbackState,
        positionMs: positionMs,
        durationMs: durationMs,
        bufferedMs: bufferedMs,
        speed: speed,
        props: props,
      ),
      _inputColorGroup(videoParams, props),
      _outputColorGroup(videoParams, props),
      _dvGroup(videoParams),
      _pipelineGroup(props),
    ]);
  }

  // ── 播放状态 ────────────────────────────────────────────────

  DebugMetricGroup _playbackGroup({
    required String playbackState,
    required int positionMs,
    required int durationMs,
    required int bufferedMs,
    required double speed,
    required Map<String, String> props,
  }) {
    final fps = props['estimated-vf-fps'] ?? '-';
    final drop = props['frame-drop-count'] ?? '-';
    final decDrop = props['decoder-frame-drop-count'] ?? '-';
    return DebugMetricGroup(
      title: '播放',
      rows: [
        DebugMetricRow(
          '状态',
          playbackState.toUpperCase(),
          severity: playbackState == 'playing'
              ? Severity.good
              : playbackState == 'paused'
                  ? Severity.warn
                  : Severity.error,
        ),
        DebugMetricRow('位置', '${_fmt(positionMs)} / ${_fmt(durationMs)}'),
        DebugMetricRow('缓冲', '${bufferedMs}ms'),
        DebugMetricRow('倍速', speed.toStringAsFixed(2)),
        DebugMetricRow('实际帧率', fps),
        DebugMetricRow(
          '丢帧',
          '渲染 $drop / 解码 $decDrop',
          severity: _dropSeverity(drop, decDrop),
        ),
      ],
    );
  }

  Severity _dropSeverity(String render, String decode) {
    final r = int.tryParse(render) ?? 0;
    final d = int.tryParse(decode) ?? 0;
    if (r > 100 || d > 100) return Severity.error;
    if (r > 10 || d > 10) return Severity.warn;
    return Severity.good;
  }

  // ── HDR 输入（片源真相）─────────────────────────────────────

  DebugMetricGroup _inputColorGroup(
    VideoColorInfo? v,
    Map<String, String> props,
  ) {
    if (v == null) {
      return const DebugMetricGroup(
        title: 'HDR 输入',
        rows: [DebugMetricRow('状态', '无视频参数（未起播）', severity: Severity.warn)],
        highlight: true,
      );
    }
    return DebugMetricGroup(
      title: 'HDR 输入',
      highlight: true,
      rows: [
        DebugMetricRow(
          '色彩',
          '${v.primaries.isEmpty ? "-" : v.primaries} / '
              '${v.gamma.isEmpty ? "-" : v.gamma}',
          severity: v.isHdr ? Severity.good : Severity.normal,
        ),
        DebugMetricRow(
          '位深',
          '${v.bitDepth}bit · ${v.pixelFormat.isEmpty ? "-" : v.pixelFormat}',
        ),
        DebugMetricRow('分辨率', '${v.width}×${v.height}'),
        if (v.sigPeak > 0)
          DebugMetricRow('信号峰值', '${v.sigPeak.toStringAsFixed(0)} nits'),
        if (v.maxLuma > 0)
          DebugMetricRow(
            '亮度范围',
            '${v.minLuma.toStringAsFixed(4)} ~ '
                '${v.maxLuma.toStringAsFixed(0)} nits',
          ),
        DebugMetricRow(
          '编码',
          props['video-format'] ?? '-',
        ),
        DebugMetricRow(
          '硬解',
          props['hwdec-current'] ?? '-',
          severity: (props['hwdec-current'] ?? '').isEmpty ||
                  props['hwdec-current'] == 'no'
              ? Severity.warn
              : Severity.good,
        ),
      ],
    );
  }

  // ── HDR 输出（实际渲染）─────────────────────────────────────

  DebugMetricGroup _outputColorGroup(
    VideoColorInfo? input,
    Map<String, String> props,
  ) {
    final targetPrim = props['target-prim'] ?? '-';
    final targetTrc = props['target-trc'] ?? '-';
    final toneMapping = props['tone-mapping'] ?? '-';
    final toneMode = props['tone-mapping-mode'] ?? '-';
    final computePeak = props['hdr-compute-peak'] ?? '-';

    // 输出是否真的在 HDR：target-trc 为 pq/hlg
    final isHdrOut = targetTrc == 'pq' || targetTrc == 'hlg';
    final isDv = input?.isDolbyVision ?? false;
    // DV 应使用 bt.2390 + hybrid（697 修复点）
    final dvMappingOk = !isDv || toneMapping == 'bt.2390';

    return DebugMetricGroup(
      title: 'HDR 输出',
      highlight: true,
      rows: [
        // 路径取适配器结论（含「纹理/Surface」「直出/映射」语义），
        // 但状态色按 target-trc 判——两者数据源不同（前者看会话配置，
        // 后者看 mpv 实际属性），用同一个判据才不会自相矛盾。
        DebugMetricRow(
          '路径',
          _adapter.mpvHdrOutputStatus,
          severity: isHdrOut ? Severity.good : Severity.normal,
        ),
        DebugMetricRow(
          '目标色彩',
          '$targetPrim / $targetTrc',
          severity: isHdrOut ? Severity.good : Severity.normal,
        ),
        DebugMetricRow(
          '色调映射',
          isDv ? '$toneMapping ($toneMode)' : toneMapping,
          severity: dvMappingOk ? Severity.good : Severity.error,
        ),
        if (isDv)
          DebugMetricRow(
            'DV 映射',
            dvMappingOk ? 'bt.2390（正确）' : '$toneMapping（应为 bt.2390）',
            severity: dvMappingOk ? Severity.good : Severity.error,
          ),
        DebugMetricRow('峰值计算', computePeak),
        DebugMetricRow('显示 HDR', _fmtBool(_adapter.mpvDisplayHdr)),
      ],
    );
  }

  // ── 杜比视界诊断 ────────────────────────────────────────────

  DebugMetricGroup _dvGroup(VideoColorInfo? v) {
    if (v == null || !v.isDolbyVision) {
      return const DebugMetricGroup(
        title: '杜比视界',
        rows: [DebugMetricRow('状态', '非 DV 内容')],
      );
    }
    final profile = v.doviProfile;
    // P5 是单层 IPT 色彩，libplacebo 必须处理元数据才能正确显示
    final isP5 = profile == 5;
    return DebugMetricGroup(
      title: '杜比视界',
      highlight: true,
      rows: [
        DebugMetricRow(
          'Profile',
          '${v.doviLabel}${isP5 ? '（单层 IPT）' : ''}',
          severity: Severity.good,
        ),
        if (v.doviLevel > 0) DebugMetricRow('Level', '${v.doviLevel}'),
        DebugMetricRow(
          '识别状态',
          _adapter.isDvContent ? '已识别为 DV' : '未识别（按普通 HDR 处理）',
          severity: _adapter.isDvContent ? Severity.good : Severity.error,
        ),
        DebugMetricRow(
          '渲染后端',
          _renderBackendLabel(),
          severity: _renderBackendSupportsDv() ? Severity.good : Severity.warn,
        ),
        if (isP5 && !_renderBackendSupportsDv())
          const DebugMetricRow(
            'P5 风险',
            '当前后端不支持 DV 元数据，画面会偏色',
            severity: Severity.error,
          ),
      ],
    );
  }

  // ── 渲染管线 ────────────────────────────────────────────────

  DebugMetricGroup _pipelineGroup(Map<String, String> props) {
    return DebugMetricGroup(
      title: '渲染管线',
      rows: [
        DebugMetricRow('vo', props['current-vo'] ?? _adapter.mpvCurrentVo ?? '-'),
        DebugMetricRow(
          'gpu-api',
          props['gpu-api'] ?? '-',
        ),
        DebugMetricRow(
          'gpu-context',
          props['gpu-context'] ?? _adapter.mpvGpuContext ?? '-',
        ),
        if (props['d3d11-output-format'] != null)
          DebugMetricRow('D3D11 格式', props['d3d11-output-format']!),
        if (props['d3d11-output-csp'] != null)
          DebugMetricRow('D3D11 CSP', props['d3d11-output-csp']!),
        DebugMetricRow('视频路径', _adapter.mpvActualVideoOutput),
        if (_adapter.mpvSurfaceId != null)
          DebugMetricRow('Surface', _adapter.mpvSurfaceId!),
        if (_adapter.mpvSurfaceError != null)
          DebugMetricRow(
            'Surface 错误',
            _adapter.mpvSurfaceError!,
            severity: Severity.error,
          ),
      ],
    );
  }

  /// 渲染后端标签（带 DV 能力结论，而非光秃秃的 context 名）。
  ///
  /// libplacebo 的 DV 处理需要 compute shader：
  /// - Windows：D3D11 ✅
  /// - 鸿蒙：Vulkan（ohosvk）✅
  /// - 安卓：OpenGL ES（libplacebo Vulkan 被禁用）❌
  ///
  /// 面板直接给出「支持/不支持」比让用户自己对照 context 名有用得多。
  String _renderBackendLabel() {
    final ctx = _adapter.mpvGpuContext ?? '';
    if (ctx.isEmpty) return '-';
    return '$ctx · ${_renderBackendSupportsDv() ? "支持 DV" : "不支持 DV"}';
  }

  /// 当前渲染后端是否支持 DV 元数据（libplacebo compute）。
  bool _renderBackendSupportsDv() {
    final ctx = (_adapter.mpvGpuContext ?? '').toLowerCase();
    // d3d11（Windows）/ ohosvk、vulkan（鸿蒙）支持
    return ctx.contains('d3d11') ||
        ctx.contains('vulkan') ||
        ctx.contains('ohosvk');
  }

  // ── 格式化 ──────────────────────────────────────────────────

  static String _fmt(int ms) {
    if (ms <= 0) return '00:00';
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  static String _fmtBool(bool? v) => v == null ? '未知' : (v ? '支持' : '不支持');
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/decoder_report.dart';
import 'package:himi_syncwatch/services/diagnostic_export.dart';

class SyncDebugPanel extends ConsumerStatefulWidget {
  final bool isHost;
  final String rtmChannel;
  final String rtmStatus;
  final String metadataTestResult;
  final String voStatus;
  final String hdrType;
  final bool isSinglePlayer;

  // 播放状态
  final String playbackState;
  final String mediaStatusStr;
  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final int mediaBitrate;
  final String mediaFormat;

  // 视频信息
  final String videoCodecName;
  final String videoResolution;
  final double videoFps;
  final int videoBitrate;
  final String pixelFormat;
  final int doviProfile;

  // 音频信息
  final String audioCodecName;
  final int audioSampleRate;
  final int audioChannels;
  final int audioBitrate;
  final String stereoDownmix;

  /// 当前生效的 `audio.avfilter` 取证（含判定用 codec），iOS TrueHD
  /// 无声排障用：区分「滤镜没写入」vs「写入了仍无声」。
  final String audioFilter;

  /// fvp 纹理句柄：null=纹理未创建（UI 转圈），非 null 仍黑=纹理存在
  /// 但无帧合成——Android 盒子黑帧（Impeller/插件错配）屏上取证用。
  final int? textureId;

  /// `textureSize`（GL FBO 尺寸），未 resolve 时为 '-'。
  final String textureSize;

  /// 生效的视频输出通道（texture/tunnel/surfaceView）——黑屏分叉时的
  /// 产物身份项：同一台设备哪一档出画面直接记进导出报告。
  final String videoOutput;

  /// 当前生效的 `video.avfilter` 取证（非标尺寸规范化滤镜）：
  /// `(未写入)`=没触发过；`(无)`=尺寸已对齐或已清；串=实际写入值。
  final String videoFilter;

  /// 截帧取证结果（mdk snapshot 平均亮度）：null=未截过。
  /// 判读：非黑=mdk 已渲染出帧、黑在 Flutter 合成侧；黑/null=mdk
  /// 渲染输出即黑。
  final String? snapshotInfo;

  /// 触发截帧取证（面板相机按钮），null=隐藏按钮。
  final VoidCallback? onSnapshot;

  // 解码器
  final String decodeMode;

  /// 用户配置的解码器列表
  final String actualVideoDecoders;

  /// mdk `video.decoder` 属性原值。该字段名与内容不符（实测返回
  /// `scale=3840x1608` 之类），单列展示以便与实际解码器对照。
  final String mdkRawDecoder;

  /// 实际生效的解码器：框架名来自 mdk 事件，底层 codec 名为平台预选推断
  final DecoderReport decoderReport;

  final String audioBackend;

  /// 设备 Dolby Vision 硬件解码能力摘要（仅 DV 内容时非空）
  final String dvCapability;

  /// 产物身份自证（版本 + 原生通道是否进包），与完整诊断报告共用
  final String buildSummary;

  // 卡顿诊断
  final String stallSummary;
  final int bufProgress;
  final bool deepLogActive;
  final String Function() onExportStutter;

  final ValueChanged<Offset> onDrag;

  const SyncDebugPanel({
    super.key,
    required this.isHost,
    required this.rtmChannel,
    required this.rtmStatus,
    required this.metadataTestResult,
    required this.voStatus,
    required this.hdrType,
    required this.isSinglePlayer,
    required this.playbackState,
    required this.mediaStatusStr,
    required this.positionMs,
    required this.durationMs,
    required this.bufferedMs,
    required this.mediaBitrate,
    required this.mediaFormat,
    required this.videoCodecName,
    required this.videoResolution,
    required this.videoFps,
    required this.videoBitrate,
    required this.pixelFormat,
    required this.doviProfile,
    required this.audioCodecName,
    required this.audioSampleRate,
    required this.audioChannels,
    required this.audioBitrate,
    required this.stereoDownmix,
    required this.audioFilter,
    required this.textureId,
    required this.textureSize,
    this.videoOutput = 'texture',
    this.videoFilter = '(未写入)',
    this.snapshotInfo,
    this.onSnapshot,
    required this.decodeMode,
    required this.actualVideoDecoders,
    required this.mdkRawDecoder,
    required this.decoderReport,
    required this.audioBackend,
    required this.dvCapability,
    required this.buildSummary,
    required this.stallSummary,
    required this.bufProgress,
    required this.deepLogActive,
    required this.onExportStutter,
    required this.onDrag,
  });

  @override
  ConsumerState<SyncDebugPanel> createState() => _SyncDebugPanelState();
}

class _SyncDebugPanelState extends ConsumerState<SyncDebugPanel> {
  bool _sectionPlayback = true;
  bool _sectionVideo = true;
  bool _sectionAudio = true;
  bool _sectionDecoder = false;
  bool _sectionStutter = true;
  bool _sectionConnection = false;
  bool _sectionLog = false;

  @override
  Widget build(BuildContext context) {
    final logs = LogService().entries;
    final decodeModeLabel =
        AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ??
            '-';

    // 播放状态颜色
    final stateColor = widget.playbackState == 'playing'
        ? Colors.green
        : widget.playbackState == 'paused'
            ? Colors.amber
            : Colors.red;
    // 媒体状态颜色
    final statusColor = widget.mediaStatusStr == 'buffering' ||
            widget.mediaStatusStr == 'stalled'
        ? Colors.amber
        : widget.mediaStatusStr == 'loaded' ||
                widget.mediaStatusStr == 'buffered' ||
                widget.mediaStatusStr == 'prepared'
            ? Colors.green
            : Colors.white54;

    return Container(
      width: 330,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 标题栏 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onPanUpdate: (d) => widget.onDrag(d.delta),
                  behavior: HitTestBehavior.opaque,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.drag_indicator, color: Colors.green, size: 16),
                      SizedBox(width: 6),
                      Text('播放调试',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(
                        ClipboardData(text: _exportDiagnostics()));
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('诊断信息已复制')));
                  },
                  child:
                      const Icon(Icons.copy, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => LogService().shareLogs(),
                  child:
                      const Icon(Icons.share, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .update(showSyncDebug: false),
                  child:
                      const Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ],
            ),
          ),

          // ── 内容区 ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 播放状态 ──
                  _buildSectionHeader('播放状态', _sectionPlayback, () {
                    setState(() => _sectionPlayback = !_sectionPlayback);
                  }),
                  if (_sectionPlayback) ...[
                    _debugRowColored(
                        '状态', widget.playbackState.toUpperCase(), stateColor),
                    _debugRowColored('媒体', widget.mediaStatusStr, statusColor),
                    _debugRow('位置', _formatMs(widget.positionMs)),
                    _debugRow('时长', _formatMs(widget.durationMs)),
                    _debugRow('缓冲区', '${widget.bufferedMs}ms'),
                    _debugRow('码率',
                        DiagnosticExport.formatBitrate(widget.mediaBitrate)),
                    _debugRow(
                        '封装',
                        widget.mediaFormat.isNotEmpty
                            ? widget.mediaFormat
                            : '-'),
                  ],

                  const SizedBox(height: 4),

                  // ── 视频信息 ──
                  _buildSectionHeader('视频', _sectionVideo, () {
                    setState(() => _sectionVideo = !_sectionVideo);
                  }),
                  if (_sectionVideo) ...[
                    _debugRow('编码', widget.videoCodecName),
                    _debugRow('分辨率', widget.videoResolution),
                    _debugRow(
                        '帧率', DiagnosticExport.formatFps(widget.videoFps)),
                    _debugRow('码率',
                        DiagnosticExport.formatBitrate(widget.videoBitrate)),
                    _debugRow('像素格式', widget.pixelFormat),
                    if (widget.doviProfile > 0)
                      _debugRow('DOVI', 'P${widget.doviProfile}'),
                    if (widget.hdrType != 'SDR')
                      _debugRow('HDR', widget.hdrType),
                    // 黑帧分叉取证：null=纹理未创建；非 null 仍黑=无帧合成
                    _debugRow('纹理',
                        '${widget.textureId ?? 'null'} | ${widget.textureSize}'),
                    _debugRow('输出', widget.videoOutput),
                    _debugRow('视频滤镜', widget.videoFilter),
                    if (widget.onSnapshot != null) _snapshotRow(),
                  ],

                  const SizedBox(height: 4),

                  // ── 音频信息 ──
                  _buildSectionHeader('音频', _sectionAudio, () {
                    setState(() => _sectionAudio = !_sectionAudio);
                  }),
                  if (_sectionAudio) ...[
                    _debugRow('编码', widget.audioCodecName),
                    _debugRow(
                        '采样率',
                        widget.audioSampleRate > 0
                            ? '${widget.audioSampleRate}Hz'
                            : '-'),
                    _debugRow(
                        '声道',
                        widget.audioChannels > 0
                            ? '${widget.audioChannels}ch'
                            : '-'),
                    _debugRow('码率',
                        DiagnosticExport.formatBitrate(widget.audioBitrate)),
                    _debugRow('降混', widget.stereoDownmix),
                    _debugRow('音频滤镜', widget.audioFilter),
                  ],

                  const SizedBox(height: 4),

                  // ── 解码器 ──
                  _buildSectionHeader('解码器', _sectionDecoder, () {
                    setState(() => _sectionDecoder = !_sectionDecoder);
                  }),
                  if (_sectionDecoder) ...[
                    _debugRow('模式', decodeModeLabel),
                    _debugRow('配置', widget.actualVideoDecoders),
                    _debugRow('实际解码', widget.decoderReport.video.display),
                    _debugRow('mdk原值', widget.mdkRawDecoder),
                    _debugRow('音频实际', widget.decoderReport.audio.display),
                    _debugRow('探测预选',
                        DiagnosticExport.formatPredicted(widget.decoderReport)),
                    if (widget.dvCapability.isNotEmpty)
                      _debugRow('DV硬解', widget.dvCapability),
                    _debugRow('音频后端', widget.audioBackend),
                  ],

                  // ── 卡顿诊断 ──
                  const SizedBox(height: 4),
                  _buildSectionHeader('卡顿', _sectionStutter, () {
                    setState(() => _sectionStutter = !_sectionStutter);
                  }),
                  if (_sectionStutter) ...[
                    if (widget.stallSummary.isEmpty)
                      _debugRow('状态', '采集中…')
                    else
                      ...widget.stallSummary.trim().split('\n').map((line) {
                        final idx = line.indexOf(':');
                        if (idx <= 0) return _debugRow('', line);
                        return _debugRow(line.substring(0, idx).trim(),
                            line.substring(idx + 1).trim());
                      }),
                    _debugRow(
                        '缓冲进度',
                        widget.bufProgress < 0
                            ? '-'
                            : '${widget.bufProgress}%'),
                    _debugRow(
                        '深度诊断', widget.deepLogActive ? '开(实测fps)' : '关(设置中开启)'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制卡顿诊断',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.greenAccent,
                          side: const BorderSide(color: Colors.greenAccent),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () async {
                          final text = widget.onExportStutter();
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('卡顿诊断已复制到剪贴板'),
                                duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── 连接信息（仅房间模式）──
                  if (!widget.isSinglePlayer) ...[
                    const SizedBox(height: 4),
                    _buildSectionHeader('连接', _sectionConnection, () {
                      setState(() => _sectionConnection = !_sectionConnection);
                    }),
                    if (_sectionConnection) ...[
                      _debugRow('角色', widget.isHost ? '主持人' : '观众'),
                      _debugRow('RTM 频道', widget.rtmChannel),
                      _debugRow('RTM 状态', widget.rtmStatus),
                      _debugRow('Metadata', widget.metadataTestResult),
                    ],
                  ],

                  const SizedBox(height: 4),

                  // ── 运行日志 ──
                  _buildSectionHeader('日志 (${logs.length})', _sectionLog, () {
                    setState(() => _sectionLog = !_sectionLog);
                  }),
                  if (_sectionLog && logs.isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        reverse: true,
                        itemCount: logs.length > 50 ? 50 : logs.length,
                        itemBuilder: (_, i) {
                          final idx = logs.length - 1 - i;
                          return Text(
                            logs[idx],
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontFamily: 'monospace'),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMs(int ms) => DiagnosticExport.formatClock(ms);

  /// 播放诊断/视频/音频三段：与播放器完整报告共用同一组装函数，
  /// 帧率/码率 0 时统一输出 `-`（此前这里用原始插值，`0kbps`/长小数
  /// 与面板 UI 行互相矛盾）。
  String _buildQuickSnapshot() => DiagnosticExport.buildQuick(
        playbackState: widget.playbackState,
        mediaStatus: widget.mediaStatusStr,
        position: _formatMs(widget.positionMs),
        duration: _formatMs(widget.durationMs),
        bufferedMs: widget.bufferedMs,
        mediaBitrate: widget.mediaBitrate,
        mediaFormat: widget.mediaFormat,
        videoCodec: widget.videoCodecName,
        videoResolution: widget.videoResolution,
        videoFps: widget.videoFps,
        videoBitrate: widget.videoBitrate,
        pixelFormat: widget.pixelFormat,
        doviProfile: widget.doviProfile,
        hdrType: widget.hdrType,
        audioCodec: widget.audioCodecName,
        audioSampleRate: widget.audioSampleRate,
        audioChannels: widget.audioChannels,
        audioBitrate: widget.audioBitrate,
        stereoDownmix: widget.stereoDownmix,
        audioFilter: widget.audioFilter,
        textureId: widget.textureId,
        textureSize: widget.textureSize,
        videoFilter: widget.videoFilter,
      );

  String _exportDiagnostics() {
    final buf = StringBuffer();
    buf.writeln(widget.buildSummary);
    buf.writeln(_buildQuickSnapshot());
    buf.writeln();
    buf.writeln('=== 解码器 ===');
    buf.writeln('模式: ${widget.decodeMode} | 配置: ${widget.actualVideoDecoders}');
    buf.writeln('实际解码: ${widget.decoderReport.video.display}');
    buf.writeln('mdk原值: ${widget.mdkRawDecoder}');
    buf.writeln('音频实际: ${widget.decoderReport.audio.display}');
    buf.writeln(DiagnosticExport.formatPredicted(widget.decoderReport));
    if (widget.dvCapability.isNotEmpty) {
      buf.writeln('DV硬解能力: ${widget.dvCapability}');
    }
    buf.writeln('音频后端: ${widget.audioBackend}');
    buf.writeln();
    buf.writeln('=== 日志 (最近20条) ===');
    final logs = LogService().entries;
    final start = logs.length > 20 ? logs.length - 20 : 0;
    for (var i = start; i < logs.length; i++) {
      buf.writeln(logs[i]);
    }
    return buf.toString();
  }

  Widget _buildSectionHeader(String title, bool expanded, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(expanded ? Icons.expand_more : Icons.chevron_right,
              color: Colors.green, size: 16),
          const SizedBox(width: 4),
          Text(title,
              style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  /// 截帧取证行：显示最近一次 snapshot 亮度结果 + 触发按钮。
  Widget _snapshotRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 65,
            child: Text('截帧',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(widget.snapshotInfo ?? '点击右侧取帧',
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
          GestureDetector(
            key: const Key('snapshotProbeButton'),
            onTap: widget.onSnapshot,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.camera_alt_outlined,
                  size: 14, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugRowColored(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

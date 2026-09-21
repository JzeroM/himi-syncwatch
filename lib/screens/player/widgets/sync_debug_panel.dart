import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';

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

  // 解码器
  final String decodeMode;
  final String actualVideoDecoders;
  final String audioBackend;

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
    required this.decodeMode,
    required this.actualVideoDecoders,
    required this.audioBackend,
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
  bool _sectionConnection = false;
  bool _sectionLog = false;

  @override
  Widget build(BuildContext context) {
    final logs = LogService().entries;
    final decodeModeLabel = AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ?? '-';

    // 播放状态颜色
    final stateColor = widget.playbackState == 'playing' ? Colors.green :
                       widget.playbackState == 'paused' ? Colors.amber : Colors.red;
    // 媒体状态颜色
    final statusColor = widget.mediaStatusStr == 'buffering' ? Colors.amber :
                        widget.mediaStatusStr == 'loaded' ? Colors.green : Colors.white54;

    return Container(
      width: 330,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 标题栏 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
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
                      Text('播放调试', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _exportDiagnostics()));
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
                  },
                  child: const Icon(Icons.copy, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => LogService().shareLogs(),
                  child: const Icon(Icons.share, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => ref.read(settingsProvider.notifier).update(showSyncDebug: false),
                  child: const Icon(Icons.close, color: Colors.white54, size: 16),
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
                    _debugRowColored('状态', widget.playbackState.toUpperCase(), stateColor),
                    _debugRowColored('媒体', widget.mediaStatusStr, statusColor),
                    _debugRow('位置', _formatMs(widget.positionMs)),
                    _debugRow('时长', _formatMs(widget.durationMs)),
                    _debugRow('缓冲区', '${widget.bufferedMs}ms'),
                    _debugRow('码率', widget.mediaBitrate > 0 ? '${widget.mediaBitrate}kbps' : '-'),
                    _debugRow('封装', widget.mediaFormat.isNotEmpty ? widget.mediaFormat : '-'),
                  ],

                  const SizedBox(height: 4),

                  // ── 视频信息 ──
                  _buildSectionHeader('视频', _sectionVideo, () {
                    setState(() => _sectionVideo = !_sectionVideo);
                  }),
                  if (_sectionVideo) ...[
                    _debugRow('编码', widget.videoCodecName),
                    _debugRow('分辨率', widget.videoResolution),
                    _debugRow('帧率', widget.videoFps > 0 ? '${widget.videoFps.toStringAsFixed(1)}fps' : '-'),
                    _debugRow('码率', widget.videoBitrate > 0 ? '${widget.videoBitrate}kbps' : '-'),
                    _debugRow('像素格式', widget.pixelFormat),
                    if (widget.doviProfile > 0)
                      _debugRow('DOVI', 'P${widget.doviProfile}'),
                    if (widget.hdrType != 'SDR')
                      _debugRow('HDR', widget.hdrType),
                  ],

                  const SizedBox(height: 4),

                  // ── 音频信息 ──
                  _buildSectionHeader('音频', _sectionAudio, () {
                    setState(() => _sectionAudio = !_sectionAudio);
                  }),
                  if (_sectionAudio) ...[
                    _debugRow('编码', widget.audioCodecName),
                    _debugRow('采样率', widget.audioSampleRate > 0 ? '${widget.audioSampleRate}Hz' : '-'),
                    _debugRow('声道', widget.audioChannels > 0 ? '${widget.audioChannels}ch' : '-'),
                    _debugRow('码率', widget.audioBitrate > 0 ? '${widget.audioBitrate}kbps' : '-'),
                    _debugRow('降混', widget.stereoDownmix),
                  ],

                  const SizedBox(height: 4),

                  // ── 解码器 ──
                  _buildSectionHeader('解码器', _sectionDecoder, () {
                    setState(() => _sectionDecoder = !_sectionDecoder);
                  }),
                  if (_sectionDecoder) ...[
                    _debugRow('模式', decodeModeLabel),
                    _debugRow('解码器', widget.actualVideoDecoders),
                    _debugRow('音频后端', widget.audioBackend),
                    _debugRow('视频输出', widget.voStatus),
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
                            style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
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

  String _formatMs(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final milli = ms % 1000;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m${s.toString().padLeft(2, '0')}s';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${(milli ~/ 100)}';
  }

  String _exportDiagnostics() {
    final buf = StringBuffer();
    buf.writeln('=== 播放诊断 ===');
    buf.writeln('状态: ${widget.playbackState} | 媒体: ${widget.mediaStatusStr}');
    buf.writeln('位置: ${_formatMs(widget.positionMs)} / ${_formatMs(widget.durationMs)}');
    buf.writeln('缓冲区: ${widget.bufferedMs}ms');
    buf.writeln('码率: ${widget.mediaBitrate}kbps | 封装: ${widget.mediaFormat}');
    buf.writeln();
    buf.writeln('=== 视频 ===');
    buf.writeln('编码: ${widget.videoCodecName} | 分辨率: ${widget.videoResolution}');
    buf.writeln('帧率: ${widget.videoFps}fps | 码率: ${widget.videoBitrate}kbps');
    buf.writeln('像素: ${widget.pixelFormat} | DOVI: ${widget.doviProfile > 0 ? "P${widget.doviProfile}" : "-"}');
    buf.writeln('HDR: ${widget.hdrType}');
    buf.writeln();
    buf.writeln('=== 音频 ===');
    buf.writeln('编码: ${widget.audioCodecName} | 采样率: ${widget.audioSampleRate}Hz');
    buf.writeln('声道: ${widget.audioChannels}ch | 码率: ${widget.audioBitrate}kbps');
    buf.writeln('降混: ${widget.stereoDownmix}');
    buf.writeln();
    buf.writeln('=== 解码器 ===');
    buf.writeln('模式: ${widget.decodeMode} | 解码器: ${widget.actualVideoDecoders}');
    buf.writeln('音频后端: ${widget.audioBackend} | VO: ${widget.voStatus}');
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
          Icon(expanded ? Icons.expand_more : Icons.chevron_right, color: Colors.green, size: 16),
          const SizedBox(width: 4),
          Text(title, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
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
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

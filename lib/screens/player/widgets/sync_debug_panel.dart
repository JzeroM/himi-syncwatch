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
  final String videoCodec;
  final String videoResolution;
  final String voStatus;
  final String decodeMode;
  final String actualDecoder;
  final String hdrType;
  final bool isSinglePlayer;

  // 播放诊断数据
  final int bufferedMs;
  final int mediaBitrate;
  final double videoFps;
  final int audioSampleRate;
  final int audioChannels;
  final String mediaFormat;

  final ValueChanged<Offset> onDrag;

  const SyncDebugPanel({
    super.key,
    required this.isHost,
    required this.rtmChannel,
    required this.rtmStatus,
    required this.metadataTestResult,
    required this.videoCodec,
    required this.videoResolution,
    required this.voStatus,
    required this.decodeMode,
    required this.actualDecoder,
    required this.hdrType,
    required this.isSinglePlayer,
    required this.bufferedMs,
    required this.mediaBitrate,
    required this.videoFps,
    required this.audioSampleRate,
    required this.audioChannels,
    required this.mediaFormat,
    required this.onDrag,
  });

  @override
  ConsumerState<SyncDebugPanel> createState() => _SyncDebugPanelState();
}

class _SyncDebugPanelState extends ConsumerState<SyncDebugPanel> {
  bool _sectionPlayback = true;
  bool _sectionDevice = true;
  bool _sectionConnection = false;
  bool _sectionLog = false;

  @override
  Widget build(BuildContext context) {
    final logs = LogService().entries;
    final decodeModeLabel = AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ?? '-';

    return Container(
      width: 320,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
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
                // 复制日志
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: LogService().exportAll()));
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已复制')));
                  },
                  child: const Icon(Icons.copy, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                // 分享日志
                GestureDetector(
                  onTap: () => LogService().shareLogs(),
                  child: const Icon(Icons.share, color: Colors.white54, size: 16),
                ),
                const SizedBox(width: 8),
                // 关闭
                GestureDetector(
                  onTap: () => ref.read(settingsProvider.notifier).update(showSyncDebug: false),
                  child: const Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ],
            ),
          ),

          // 内容区
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
                    _debugRow('缓冲区', '${widget.bufferedMs}ms'),
                    _debugRow('媒体码率', widget.mediaBitrate > 0 ? '${widget.mediaBitrate}kbps' : '-'),
                    _debugRow('视频帧率', widget.videoFps > 0 ? '${widget.videoFps.toStringAsFixed(1)}fps' : '-'),
                    _debugRow('音频采样率', widget.audioSampleRate > 0 ? '${widget.audioSampleRate}Hz' : '-'),
                    _debugRow('声道数', widget.audioChannels > 0 ? '${widget.audioChannels}ch' : '-'),
                    _debugRow('封装格式', widget.mediaFormat.isNotEmpty ? widget.mediaFormat : '-'),
                  ],

                  const SizedBox(height: 4),

                  // ── 设备信息 ──
                  _buildSectionHeader('设备信息', _sectionDevice, () {
                    setState(() => _sectionDevice = !_sectionDevice);
                  }),
                  if (_sectionDevice) ...[
                    _debugRow('视频编码', widget.videoCodec),
                    _debugRow('分辨率', widget.videoResolution),
                    _debugRow('视频输出', widget.voStatus),
                    _debugRow('解码模式', decodeModeLabel),
                    _debugRow('实际解码器', widget.actualDecoder.isNotEmpty ? widget.actualDecoder : '检测中...'),
                    if (widget.hdrType != 'SDR')
                      _debugRow('HDR 类型', widget.hdrType),
                  ],

                  // ── 连接信息（仅房间模式）──
                  if (!widget.isSinglePlayer) ...[
                    const SizedBox(height: 4),
                    _buildSectionHeader('连接信息', _sectionConnection, () {
                      setState(() => _sectionConnection = !_sectionConnection);
                    }),
                    if (_sectionConnection) ...[
                      _debugRow('角色', widget.isHost ? '主持人' : '观众'),
                      _debugRow('RTM 频道', widget.rtmChannel),
                      _debugRow('RTM 状态', widget.rtmStatus),
                      _debugRow('Metadata 自检', widget.metadataTestResult),
                    ],
                  ],

                  const SizedBox(height: 4),

                  // ── 运行日志 ──
                  _buildSectionHeader('运行日志 (${logs.length})', _sectionLog, () {
                    setState(() => _sectionLog = !_sectionLog);
                  }),
                  if (_sectionLog && logs.isNotEmpty)
                    SizedBox(
                      height: 200,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

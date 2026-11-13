import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:himi_syncwatch/services/debug/debug_metrics.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';

/// 697：播放调试面板（完全重写，替代旧 `SyncDebugPanel`）。
///
/// ## 为什么重写
///
/// 旧面板（665 行）定位是「同步调试」，混了 RTM 状态、时钟校准、房间信息、
/// 解码器报告、日志列表——HDR/DV 参数只占两行，排查时找不到重点。
///
/// 新面板只做一件事：**显示播放中的实时参数，重点是 HDR / DV**。
///
/// ## 设计
///
/// - **半透明可拖动**：背景 alpha 0.72（旧 0.92 太实，挡住画面）
/// - **数据驱动**：外部提供 [fetch]，返回 [DebugMetrics] 后按分组渲染，
///   新增指标只改采集侧，UI 零改动
/// - **分组可折叠**：默认全展开（排查时不需要额外点击）
/// - **状态色**：绿=正常、琥珀=可疑、红=异常（如 DV 未识别、P5 后端不支持）
/// - **一键复制**：导出纯文本，便于贴到 issue
///
/// ## 两种使用方式
///
/// | 方式 | 场景 |
/// |---|---|
/// | 传 [fetch] | 生产（1s 轮询采集 mpv 属性） |
/// | 传 [metrics] | 测试 / 静态快照（不轮询） |
class PlaybackDebugPanel extends StatefulWidget {
  /// 生产模式：定时拉取指标。
  ///
  /// 与 [metrics] 互斥；两者都传时 [metrics] 优先（便于测试）。
  const PlaybackDebugPanel({
    super.key,
    this.fetch,
    this.metrics,
    this.exportDiagnostics,
    this.refreshInterval = const Duration(seconds: 1),
    required this.onDrag,
    required this.onClose,
  });

  /// 指标拉取回调（生产模式）。
  final Future<DebugMetrics> Function()? fetch;

  /// 静态指标（测试 / 一次性快照）。传入后不再定时拉取。
  final DebugMetrics? metrics;

  /// 「导出完整诊断」回调（返回待复制的长文本）。
  ///
  /// 面板自身只负责播放实时参数；完整诊断（时间线/卡顿/深度日志）
  /// 由播放页组装——那是页面状态，面板不该知道。
  final String Function()? exportDiagnostics;

  /// 自动刷新间隔。
  final Duration refreshInterval;

  /// 拖动回调（面板位置由父级持有）。
  final void Function(Offset delta) onDrag;

  final VoidCallback onClose;

  @override
  State<PlaybackDebugPanel> createState() => _PlaybackDebugPanelState();
}

class _PlaybackDebugPanelState extends State<PlaybackDebugPanel> {
  DebugMetrics _metrics = DebugMetrics.empty;
  Timer? _timer;
  bool _loading = true;

  /// 各分组折叠状态（默认全展开——排查时不需要额外点击）。
  final Set<String> _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    final static_ = widget.metrics;
    if (static_ != null) {
      // 静态模式：直接用给定指标，不轮询
      _metrics = static_;
      _loading = false;
      return;
    }
    unawaited(_refresh());
    _timer = Timer.periodic(widget.refreshInterval, (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final fetch = widget.fetch;
    if (fetch == null || !mounted) return;
    try {
      final m = await fetch();
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _metrics.toPlainText()));
    if (mounted) showAppToast(context, '调试信息已复制');
  }

  /// 复制完整诊断（含时间线/卡顿/深度日志，由播放页组装）。
  Future<void> _copyDiagnostics() async {
    final export = widget.exportDiagnostics;
    if (export == null) return;
    await Clipboard.setData(ClipboardData(text: export()));
    if (mounted) showAppToast(context, '完整诊断已复制');
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          // 697：0.72 而非旧的 0.92——半透明，能看穿到画面
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(),
            Flexible(
              child: _loading && _metrics.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final g in _metrics.groups) _buildGroup(g),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Row(
        children: [
          // 拖动区（标题左侧）
          Expanded(
            child: GestureDetector(
              onPanUpdate: (d) => widget.onDrag(d.delta),
              behavior: HitTestBehavior.opaque,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.drag_indicator,
                      color: Colors.greenAccent, size: 15),
                  SizedBox(width: 4),
                  Text(
                    '播放调试',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _iconButton(Icons.copy, '复制全部', _copyAll),
          if (widget.exportDiagnostics != null)
            _iconButton(Icons.description_outlined, '复制完整诊断', _copyDiagnostics),
          const SizedBox(width: 4),
          _iconButton(Icons.close, '关闭', widget.onClose),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tip,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, color: Colors.white54, size: 15),
        ),
      ),
    );
  }

  Widget _buildGroup(DebugMetricGroup g) {
    if (g.rows.isEmpty) return const SizedBox.shrink();
    final collapsed = _collapsed.contains(g.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分组标题（可点击折叠）
          GestureDetector(
            onTap: () => setState(() {
              if (collapsed) {
                _collapsed.remove(g.title);
              } else {
                _collapsed.add(g.title);
              }
            }),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 14,
                    color: g.highlight
                        ? Colors.greenAccent
                        : Colors.white38,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    g.title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: g.highlight
                          ? Colors.greenAccent
                          : Colors.white70,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            for (final r in g.rows)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 1, bottom: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        r.label,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _severityColor(r.severity),
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static Color _severityColor(Severity s) {
    switch (s) {
      case Severity.good:
        return const Color(0xFF6EE7A0);
      case Severity.warn:
        return const Color(0xFFFBBF24);
      case Severity.error:
        return const Color(0xFFF87171);
      case Severity.normal:
        return Colors.white70;
    }
  }
}

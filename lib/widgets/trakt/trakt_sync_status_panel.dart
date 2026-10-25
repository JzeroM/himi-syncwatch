import 'package:flutter/material.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';

class TraktSyncStatusPanel extends StatelessWidget {
  final TraktSyncState syncState;
  final TraktSyncProgress? live;
  final bool syncing;
  final VoidCallback onSync;

  const TraktSyncStatusPanel({
    super.key,
    required this.syncState,
    required this.live,
    required this.syncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final active = syncing || live != null;
    final statusText = active
        ? '同步中'
        : syncState.lastSuccessAt != null
            ? '已同步'
            : '等待同步';
    final statusColor =
        active ? const Color(0xFF818CF8) : const Color(0xFF34D399);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, size: 20, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                '同步概览',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            syncState.lastSuccessAt == null
                ? '上次成功：尚未同步'
                : '上次成功：${_formatTime(syncState.lastSuccessAt!)}',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: '电影', value: syncState.movies),
              const SizedBox(width: 10),
              _Metric(label: '剧集', value: syncState.shows),
              const SizedBox(width: 10),
              _Metric(label: '单集', value: syncState.episodes),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: _progressValue(),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF818CF8)),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _phaseText(),
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: syncing ? null : onSync,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('立即同步'),
            ),
          ),
        ],
      ),
    );
  }

  double? _progressValue() {
    final current = live;
    if (current == null) return null;
    if (current.phase == TraktSyncPhase.writing && current.actionsTotal > 0) {
      return (current.actionsDone / current.actionsTotal).clamp(0.0, 1.0);
    }
    if (current.phase == TraktSyncPhase.scanningServers &&
        current.serversTotal > 0) {
      return (current.serversDone / current.serversTotal).clamp(0.0, 1.0);
    }
    return null;
  }

  String _phaseText() {
    final current = live;
    if (current == null) return '正在同步…';
    switch (current.phase) {
      case TraktSyncPhase.readingRemote:
        return '正在读取 Trakt 记录…';
      case TraktSyncPhase.scanningServers:
        return '扫描服务器 ${current.serversDone}/${current.serversTotal}';
      case TraktSyncPhase.matching:
        return '正在匹配条目…';
      case TraktSyncPhase.writing:
        if (current.actionsTotal <= 0) return '没有需要写入的变更';
        return '写入进度 ${current.actionsDone}/${current.actionsTotal}';
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/cache_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/cache/cache_models.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_confirm_dialog.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

class CacheSettingsScreen extends ConsumerStatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  ConsumerState<CacheSettingsScreen> createState() =>
      _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends ConsumerState<CacheSettingsScreen> {
  CacheSnapshot? _snapshot;
  Object? _error;
  bool _scanning = true;
  CacheCategory? _clearing;
  bool _clearingAll = false;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _scanning = true;
        _error = null;
      });
    }
    try {
      final snapshot = await ref.read(appCacheServiceProvider).scan();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _scanning = false;
      });
    }
  }

  Future<void> _clear(CacheCategory category) async {
    if (_snapshot == null || _clearing != null || _clearingAll) return;
    final confirmed = await showTvConfirmDialog(
      context: context,
      title: '清理${category.label}？',
      message: _confirmMessage(category),
      confirmLabel: '清理',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = category);
    try {
      final result = await ref.read(appCacheServiceProvider).clear(category);
      await _scan(showLoading: false);
      if (!mounted) return;
      _showResult(result);
    } catch (_) {
      if (mounted) showAppToast(context, '清理失败，请重试');
    } finally {
      if (mounted) setState(() => _clearing = null);
    }
  }

  Future<void> _clearAll() async {
    if (_snapshot == null || _clearing != null || _clearingAll) return;
    final confirmed = await showTvConfirmDialog(
      context: context,
      title: '清理全部缓存？',
      message: '将清理图片缓存、弹幕缓存、临时文件和诊断日志。'
          '诊断日志删除后无法恢复；不会删除账号/服务器配置、收藏/播放进度、'
          '字幕样式、TV 配对或已保存的二维码。',
      confirmLabel: '清理',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingAll = true);
    try {
      final result = await ref.read(appCacheServiceProvider).clearAll();
      await _scan(showLoading: false);
      if (!mounted) return;
      _showResult(result);
    } catch (_) {
      if (mounted) showAppToast(context, '清理失败，请重试');
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  void _showResult(CacheClearResult result) {
    showAppToast(
      context,
      result.failures.isEmpty ? '缓存已清理' : '部分文件未能清理',
    );
  }

  String _confirmMessage(CacheCategory category) {
    switch (category) {
      case CacheCategory.images:
        return '将删除海报、头像和背景图缓存，之后会按需重新下载。不影响收藏和账号信息。';
      case CacheCategory.danmaku:
        return '将清空本次运行期间的内存弹幕缓存，不影响当前播放。';
      case CacheCategory.temp:
        return '将删除分享二维码和字幕偏移临时文件，不影响已保存到相册的二维码。';
      case CacheCategory.logs:
        return '将删除运行日志和闪退日志，清理后无法再导出历史记录。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tvMode =
        ref.watch(settingsProvider.select((settings) => settings.tvMode));
    final snapshot = _snapshot;

    return SettingsSubPage(
      pageKey: const ValueKey('cacheSettingsPage'),
      title: '缓存管理',
      children: [
        if (snapshot == null && _scanning)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (snapshot == null && _error != null)
          _CacheErrorView(error: _error!, onRetry: _scan)
        else if (snapshot != null) ...[
          _CacheSummaryCard(
            snapshot: snapshot,
            scanning: _scanning,
            clearing: _clearingAll,
            onClearAll: _clearing == null && !_clearingAll ? _clearAll : null,
          ),
          const Divider(height: 1),
          for (final category in CacheCategory.values) ...[
            _CacheRow(
              category: category,
              stat: snapshot.statOf(category),
              tvMode: tvMode,
              busy: _clearing != null || _clearingAll,
              clearing: _clearing == category,
              onTap: () => _clear(category),
            ),
            const Divider(height: 1),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Text(
              '更新包不在此列表，已安装版本会在下次启动自动清理。\n'
              '不会清理：账号/服务器配置、收藏/播放进度、字幕样式、'
              'TV 配对、已保存的二维码。\n'
              '播放器网络缓冲为运行时内存，可在「播放器 > 播放器配置 > 缓存大小」调整。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white54,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CacheErrorView extends ConsumerWidget {
  const _CacheErrorView({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode =
        ref.watch(settingsProvider.select((settings) => settings.tvMode));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('读取缓存信息失败'),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          settingsTvWrapRow(
            tvMode: tvMode,
            onTap: () => unawaited(onRetry()),
            child: FilledButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheSummaryCard extends StatelessWidget {
  const _CacheSummaryCard({
    required this.snapshot,
    required this.scanning,
    required this.clearing,
    required this.onClearAll,
  });

  final CacheSnapshot snapshot;
  final bool scanning;
  final bool clearing;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalDiskBytes;
    final stats = snapshot.diskStats;
    final canClear = onClearAll != null && snapshot.hasAny && !clearing;

    return GlassContainer(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '总缓存',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (scanning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatBytes(total),
            key: const ValueKey('cacheTotalSize'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '磁盘缓存 · 不含更新包与播放器内存缓冲',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          _CacheBar(stats: stats),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              for (final entry in stats)
                _LegendItem(
                  color: entry.key.color,
                  label: entry.key.label,
                  value: formatBytes(entry.value.bytes),
                  percent: _percent(entry.value.bytes, total),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '弹幕缓存 ${snapshot.totalDanmakuCount} 条（内存）',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
              TvFocusable(
                key: const ValueKey('cacheClearAll'),
                enabled: canClear,
                scale: 1.0,
                radius: 10,
                onTap: canClear ? onClearAll : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: canClear
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.16)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: clearing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                              color: canClear
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '清理全部',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: canClear
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white38,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _percent(int bytes, int total) {
    if (total <= 0) return '0.0%';
    return '${(bytes / total * 100).toStringAsFixed(1)}%';
  }
}

class _CacheBar extends StatelessWidget {
  const _CacheBar({required this.stats});

  final List<MapEntry<CacheCategory, CacheStat>> stats;

  @override
  Widget build(BuildContext context) {
    final active = stats.where((entry) => entry.value.bytes > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: active.isEmpty
            ? const ColoredBox(color: Colors.white12)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in active)
                    Expanded(
                      flex: entry.value.bytes,
                      child: ColoredBox(color: entry.key.color),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
    required this.percent,
  });

  final Color color;
  final String label;
  final String value;
  final String percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          '$value · $percent',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.category,
    required this.stat,
    required this.tvMode,
    required this.busy,
    required this.clearing,
    required this.onTap,
  });

  final CacheCategory category;
  final CacheStat stat;
  final bool tvMode;
  final bool busy;
  final bool clearing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && !stat.isEmpty;
    final value =
        category.isMemory ? '${stat.itemCount} 条' : formatBytes(stat.bytes);
    final row = ListTile(
      key: ValueKey('cacheRow_${category.name}'),
      leading: Icon(category.icon, color: category.color),
      title: Text(category.label),
      subtitle: Text(category.description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(width: 6),
          if (clearing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              key: ValueKey('cacheClear_${category.name}'),
              tooltip: '清理${category.label}',
              onPressed: enabled ? onTap : null,
              icon: Icon(
                Icons.delete_outline,
                color: enabled ? Colors.redAccent : Colors.white24,
              ),
            ),
        ],
      ),
      onTap: enabled ? onTap : null,
    );

    if (!enabled) return row;
    return settingsTvWrapRow(
      tvMode: tvMode,
      onTap: onTap,
      child: row,
    );
  }
}

extension _CacheCategoryUi on CacheCategory {
  String get label {
    switch (this) {
      case CacheCategory.images:
        return '图片缓存';
      case CacheCategory.danmaku:
        return '弹幕缓存';
      case CacheCategory.temp:
        return '临时文件';
      case CacheCategory.logs:
        return '诊断日志';
    }
  }

  String get description {
    switch (this) {
      case CacheCategory.images:
        return '海报、头像与背景图，清理后按需重新下载';
      case CacheCategory.danmaku:
        return '本次运行期间的弹幕匹配结果，清理不影响当前播放';
      case CacheCategory.temp:
        return '分享二维码、字幕偏移副本等临时文件';
      case CacheCategory.logs:
        return '闪退与运行日志，清理后无法导出历史记录';
    }
  }

  IconData get icon {
    switch (this) {
      case CacheCategory.images:
        return Icons.photo_library_outlined;
      case CacheCategory.danmaku:
        return Icons.chat_bubble_outline;
      case CacheCategory.temp:
        return Icons.folder_delete_outlined;
      case CacheCategory.logs:
        return Icons.description_outlined;
    }
  }

  Color get color {
    switch (this) {
      case CacheCategory.images:
        return const Color(0xFF8B5CF6);
      case CacheCategory.danmaku:
        return const Color(0xFFF472B6);
      case CacheCategory.temp:
        return const Color(0xFFF59E0B);
      case CacheCategory.logs:
        return const Color(0xFF38BDF8);
    }
  }
}

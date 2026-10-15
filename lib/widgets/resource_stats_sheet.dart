import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/library_counts.dart';
import 'package:himi_syncwatch/providers/library_counts_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/sheet_bottom_safe_area.dart';

/// 资源统计底部面板：服务器名 + 主线路标签，电影/剧集/集 × 不含多版本/包含多版本。
/// 打开即懒加载，无手动刷新按钮。
Future<void> showResourceStatsSheet(
  BuildContext context,
  EmbyServerConfig server,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ResourceStatsSheet(server: server),
  );
}

class _ResourceStatsSheet extends ConsumerStatefulWidget {
  const _ResourceStatsSheet({required this.server});

  final EmbyServerConfig server;

  @override
  ConsumerState<_ResourceStatsSheet> createState() => _ResourceStatsSheetState();
}

class _ResourceStatsSheetState extends ConsumerState<_ResourceStatsSheet> {
  @override
  void initState() {
    super.initState();
    // 打开即懒加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(libraryCountsProvider(widget.server.id).notifier)
          .ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryCountsProvider(widget.server.id));
    final counts = state.counts;
    final loading = state.loading;

    return SheetBottomSafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行：服务器名 + 主线路标签 + 关闭
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.server.label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.server.activeRouteUrl != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '主线路',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('resourceStatsClose'),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (counts == null || counts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '未能获取统计信息',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              _CountsTable(counts: counts),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CountsTable extends StatelessWidget {
  const _CountsTable({required this.counts});

  final LibraryCounts counts;

  @override
  Widget build(BuildContext context) {
    final without = counts.withoutVersions;
    final withV = counts.withVersions;
    return GlassContainer(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 表头
          Row(
            children: [
              const Expanded(flex: 2, child: SizedBox()),
              Expanded(
                flex: 2,
                child: _HeaderCell('不含多版本'),
              ),
              Expanded(
                flex: 2,
                child: _HeaderCell('包含多版本'),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          _Row(label: '电影', a: without?.movies, b: withV?.movies),
          _Row(label: '剧集', a: without?.series, b: withV?.series),
          _Row(label: '集', a: without?.episodes, b: withV?.episodes),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: Colors.white.withValues(alpha: 0.6),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.a, required this.b});

  final String label;
  final int? a;
  final int? b;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 2,
            child: _Value(a),
          ),
          Expanded(
            flex: 2,
            child: _Value(b),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.value);

  final int? value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value == null ? '—' : '$value',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

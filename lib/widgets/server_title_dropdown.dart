import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 当前 Emby 服务器标题玻璃胶囊，点击下拉切换服务器。
///
/// 双焦点语义（[onTitleTap] 非空时，TV 顶栏场景）：
/// - 名称部分：OK → [onTitleTap]（回首页）
/// - ▾ 部分：OK → 打开服务器下拉
///
/// [onTitleTap] 为空时（首页 AppBar 场景）：名称与 ▾ 点击均打开下拉，
/// 与原首页标题行为一致。
class ServerTitleDropdown extends ConsumerWidget {
  const ServerTitleDropdown({super.key, this.onTitleTap});

  /// 点击名称部分的回调；null 表示名称点击也打开服务器下拉。
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(embyConfigProvider);
    final seenServerIds = <String>{};
    final dedupedServers = <EmbyServerConfig>[];
    for (final s in ref.watch(embyServerListProvider)) {
      if (seenServerIds.add(s.serverId)) {
        dedupedServers.add(s);
      }
    }

    final label = current?.label ?? 'HIMI';

    if (dedupedServers.isEmpty) {
      // 无服务器：纯展示胶囊（有回首页回调时名称仍可聚焦触发）
      return GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        showShadow: false,
        child: onTitleTap == null
            ? _labelRow(label)
            : TvFocusable(
                onTap: onTitleTap,
                child: _labelRow(label),
              ),
      );
    }

    return Builder(
      builder: (titleContext) => GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        padding: const EdgeInsets.only(left: 12, right: 2),
        showShadow: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvFocusable(
              radius: 12,
              onTap: onTitleTap ??
                  () => _showServerMenu(
                        titleContext,
                        ref,
                        current: current,
                        servers: dedupedServers,
                      ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _labelRow(label),
              ),
            ),
            // ▾：TV 顶栏（onTitleTap 非空）为独立焦点，首页为整块点击的一部分
            TvFocusable(
              radius: 12,
              onTap: () => _showServerMenu(
                titleContext,
                ref,
                current: current,
                servers: dedupedServers,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_drop_down),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelRow(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.dns_outlined, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  /// 标题下方锚定的液态玻璃服务器下拉层（替代 Material PopupMenu）。
  void _showServerMenu(
    BuildContext titleContext,
    WidgetRef ref, {
    required EmbyServerConfig? current,
    required List<EmbyServerConfig> servers,
  }) {
    final box = titleContext.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screenW = MediaQuery.sizeOf(titleContext).width;

    showGeneralDialog<void>(
      context: titleContext,
      barrierDismissible: true,
      barrierLabel: '关闭服务器列表',
      barrierColor: Colors.black.withValues(alpha: 0.30),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) {
        var left = rect.left < 12 ? 12.0 : rect.left;
        var width = math.min(math.max(rect.width, 220.0), screenW - left - 12);
        if (left + width > screenW - 12) {
          left = math.max(12.0, screenW - 12 - width);
        }
        return Stack(
          children: [
            Positioned(
              left: left,
              top: rect.bottom + 8,
              width: width,
              child: Material(
                type: MaterialType.transparency,
                child: GlassContainer(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in servers)
                            _buildServerRow(
                              dialogContext,
                              ref,
                              s,
                              active: current?.id == s.id,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildServerRow(
    BuildContext dialogContext,
    WidgetRef ref,
    EmbyServerConfig server, {
    required bool active,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext);
        _selectServer(ref, server);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            if (active)
              const Icon(Icons.check_circle, size: 18, color: Colors.green)
            else
              const Icon(Icons.dns_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                server.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectServer(WidgetRef ref, EmbyServerConfig server) async {
    final current = ref.read(embyConfigProvider);
    if (current?.id == server.id) return;
    ref.read(embyConfigProvider.notifier).setConfig(server);
    await ref.read(embyAuthServiceProvider).saveSelectedServerId(server.id);
  }
}

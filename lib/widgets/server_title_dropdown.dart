import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 当前 Emby 服务器标题玻璃胶囊，点击/OK 打开下拉切换首页来源或服务器。
///
/// TV 模式整颗胶囊是**单个焦点**（v1.2.31）：名称与 ▾ 同属一个
/// [TvFocusable]，OK = 打开下拉；回首页不再由标题承担（遥控器
/// 返回键在非首页标签即可回首页，见 `MainShell._handleBack`）。
/// 无服务器时仍可打开下拉，用于选择 TMDB 聚合模式。
class ServerTitleDropdown extends ConsumerWidget {
  const ServerTitleDropdown({super.key});

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

    return Builder(
      builder: (titleContext) => TvFocusable(
        // 整颗胶囊一个焦点环（圆角与胶囊一致），OK 即打开服务器下拉
        radius: 24,
        onTap: () => _showServerMenu(
          titleContext,
          ref,
          current: current,
          servers: dedupedServers,
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          padding: const EdgeInsets.only(left: 12, right: 2),
          showShadow: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _labelRow(label),
                ),
              ),
              // ▾ 为纯装饰（不再单独聚焦），点击落点由外层胶囊统一接管
              const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_drop_down),
              ),
            ],
          ),
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
                          _buildModeRow(
                            dialogContext,
                            ref,
                            label: '服务器首页',
                            icon: Icons.dns_outlined,
                            tmdb: false,
                          ),
                          _buildModeRow(
                            dialogContext,
                            ref,
                            label: 'TMDB 聚合',
                            icon: Icons.local_movies_outlined,
                            tmdb: true,
                          ),
                          const Divider(height: 1),
                          if (servers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Text(
                                '未添加服务器',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          else
                            for (final s in servers)
                              _buildServerRow(
                                dialogContext,
                                ref,
                                s,
                                active: current?.id == s.id,
                                autofocus: false,
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

  Widget _buildModeRow(
    BuildContext dialogContext,
    WidgetRef ref, {
    required String label,
    required IconData icon,
    required bool tmdb,
  }) {
    final active = ref.read(settingsProvider).isTmdbHome == tmdb;
    void select() {
      Navigator.pop(dialogContext);
      if (active) return;
      ref.read(settingsProvider.notifier).update(
            homeSourceMode: tmdb ? 'tmdb' : 'server',
          );
    }

    return TvFocusable(
      key: ValueKey('homeSourceModeRow_${tmdb ? 'tmdb' : 'server'}'),
      radius: 12,
      scale: 1.0,
      autofocus: active,
      onTap: select,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle : icon,
              size: 18,
              color: active ? Colors.green : Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
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

  Widget _buildServerRow(
    BuildContext dialogContext,
    WidgetRef ref,
    EmbyServerConfig server, {
    required bool active,
    required bool autofocus,
  }) {
    void select() {
      Navigator.pop(dialogContext);
      _selectServer(ref, server);
    }

    // TV：每行一个焦点（焦点环 + 方向键遍历，v1.2.32 回归；
    // 此前是裸 InkWell，遥控器选服务器时无焦点框）
    return TvFocusable(
      key: ValueKey('serverRow_${server.id}'),
      radius: 12,
      scale: 1.0,
      autofocus: autofocus,
      onTap: select,
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

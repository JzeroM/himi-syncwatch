import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 服务器头像渐变调色板（按 serverId hash 取色，同服务器恒定色）。
const List<List<Color>> _avatarGradients = [
  [Color(0xFF43E97B), Color(0xFF38F9D7)],
  [Color(0xFF4FACFE), Color(0xFF00F2FE)],
  [Color(0xFFFA709A), Color(0xFFFEE140)],
  [Color(0xFFA18CD1), Color(0xFFB8E4FF)],
  [Color(0xFFF6D365), Color(0xFFFDA085)],
  [Color(0xFF89F7FE), Color(0xFF66A6FF)],
];

Color serverAvatarStartColor(String seed) =>
    _avatarGradients[(seed.hashCode & 0x7fffffff) % _avatarGradients.length][0];

Color serverAvatarEndColor(String seed) =>
    _avatarGradients[(seed.hashCode & 0x7fffffff) % _avatarGradients.length][1];

/// 渐变圆形头像（取服务器名首字符）。
class ServerAvatar extends StatelessWidget {
  const ServerAvatar({super.key, required this.label, this.size = 44});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final seed = label.isEmpty ? 'himi' : label;
    final letter = label.isEmpty ? 'H' : label.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [serverAvatarStartColor(seed), serverAvatarEndColor(seed)],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 延迟徽标：<100ms 绿 / <300ms 橙 / 其余红；null 不渲染。
class LatencyBadge extends StatelessWidget {
  const LatencyBadge({super.key, required this.latencyMs});

  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final ms = latencyMs;
    if (ms == null) return const SizedBox.shrink();
    final color = ms < 100
        ? Colors.greenAccent
        : (ms < 300 ? Colors.orangeAccent : Colors.redAccent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 13, color: color),
        const SizedBox(width: 2),
        Text(
          '${ms}ms',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// 电影 / 剧集计数（无数据不渲染）。
class MovieSeriesCounts extends StatelessWidget {
  const MovieSeriesCounts({super.key, required this.counts});

  final MediaCounts? counts;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    if (c == null) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 12, color: Colors.white70);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.movie_outlined, size: 14, color: Colors.white70),
        const SizedBox(width: 2),
        Text('${c.movies}', style: style),
        const SizedBox(width: 8),
        const Icon(Icons.tv, size: 14, color: Colors.white70),
        const SizedBox(width: 2),
        Text('${c.series}', style: style),
      ],
    );
  }
}

/// 卡片右上角更多菜单：编辑（仅激活）/ 上移 / 删除。
class ServerMoreMenu extends StatelessWidget {
  const ServerMoreMenu({
    super.key,
    required this.menuKey,
    required this.onDelete,
    this.onEdit,
    this.onMoveUp,
  });

  final String menuKey;
  final VoidCallback? onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey(menuKey),
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
        if (onMoveUp != null)
          const PopupMenuItem(value: 'moveUp', child: Text('上移')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
      onSelected: (value) {
        if (value == 'edit') {
          onEdit?.call();
        } else if (value == 'moveUp') {
          onMoveUp?.call();
        } else if (value == 'delete') {
          onDelete();
        }
      },
    );
  }
}

/// 列表视图服务器卡（横向玻璃卡）：头像 + 名称/副标题 + 计数/延迟 + 把手。
class ServerListCard extends StatelessWidget {
  const ServerListCard({
    super.key,
    required this.server,
    required this.isActive,
    required this.stats,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
    this.onMoveUp,
    this.dragHandle,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback onDelete;

  /// 拖拽把手（由外层 ReorderableDragStartListener 包装后传入）。
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final start = serverAvatarStartColor(server.serverId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18),
        tint: isActive ? start.withValues(alpha: 0.28) : GlassConfig.panelTintOf(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  ServerAvatar(label: server.label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                server.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight:
                                      isActive ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: Colors.greenAccent, size: 16),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${server.username} · ${server.serverUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MovieSeriesCounts(counts: stats?.counts),
                            LatencyBadge(latencyMs: stats?.latencyMs),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ServerMoreMenu(
                        menuKey: 'serverMore_${server.id}',
                        onEdit: onEdit,
                        onMoveUp: onMoveUp,
                        onDelete: onDelete,
                      ),
                      if (dragHandle != null) dragHandle!,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 网格视图服务器卡（近方形玻璃卡）：头像 + 更多菜单 / 名称 / 延迟 / 计数。
class ServerGridCard extends StatelessWidget {
  const ServerGridCard({
    super.key,
    required this.server,
    required this.isActive,
    required this.stats,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
    this.onMoveUp,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final start = serverAvatarStartColor(server.serverId);
    final end = serverAvatarEndColor(server.serverId);
    return GlassContainer(
      borderRadius: BorderRadius.circular(18),
      tint: isActive ? start.withValues(alpha: 0.28) : GlassConfig.panelTintOf(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Stack(
            children: [
              // 背景斜向渐变氛围（激活态更明显）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        start.withValues(alpha: isActive ? 0.22 : 0.10),
                        end.withValues(alpha: isActive ? 0.10 : 0.03),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ServerAvatar(label: server.label, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      server.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.check_circle,
                                        color: Colors.greenAccent, size: 14),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                server.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        ServerMoreMenu(
                          menuKey: 'serverMore_${server.id}',
                          onEdit: onEdit,
                          onMoveUp: onMoveUp,
                          onDelete: onDelete,
                        ),
                      ],
                    ),
                    const Spacer(),
                    LatencyBadge(latencyMs: stats?.latencyMs),
                    const SizedBox(height: 6),
                    MovieSeriesCounts(counts: stats?.counts),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

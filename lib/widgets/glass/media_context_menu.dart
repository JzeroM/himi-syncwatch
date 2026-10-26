import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/media_state_override_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_context_menu.dart';

/// 首页/分类/收藏页共享的长按玻璃菜单动作（Emby 联动）。
///
/// 动作按条目状态**只显示一条**，并乐观/直接调用激活服务器 Emby，成功 bump
/// 对应修订号触发相应列表刷新：
/// - 收藏/取消收藏 → `FavoriteItems`；bump `favoritesRevision`。
/// - 标记/取消已观看 → `PlayedItems`（整部剧或单集）；bump `resumeRevision`。
/// - 移除历史 → `HideFromResume` + 续播栏乐观隐藏，不清播放进度。

/// 「继续观看」横卡菜单：收藏/取消收藏 + 移除历史。
Future<void> showResumeCardMenu(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  Rect anchor, {
  String? serverId,
}) {
  return showGlassContextMenu(
    context,
    anchor: anchor,
    actions: [
      _favoriteAction(context, ref, item, serverId: serverId),
      GlassMenuAction(
        icon: Icons.delete_outline,
        label: '移除历史',
        destructive: true,
        onTap: () => _removeFromResume(context, ref, item, serverId: serverId),
      ),
    ],
  );
}

/// 海报卡菜单：收藏/取消收藏 + 标记/取消已观看（每次按状态只显示一条）。
Future<void> showPosterCardMenu(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  Rect anchor, {
  String? serverId,
}) {
  return showGlassContextMenu(
    context,
    anchor: anchor,
    actions: [
      _favoriteAction(context, ref, item, serverId: serverId),
      _watchedAction(context, ref, item, serverId: serverId),
    ],
  );
}

/// 收藏项：已收藏 → 「取消收藏」（红字），否则 → 「收藏」。
GlassMenuAction _favoriteAction(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  String? serverId,
}) {
  if (_effectiveFavorite(ref, item)) {
    return GlassMenuAction(
      icon: Icons.favorite,
      label: '取消收藏',
      destructive: true,
      onTap: () => _setFavorite(context, ref, item, false, serverId: serverId),
    );
  }
  return GlassMenuAction(
    icon: Icons.favorite_border,
    label: '收藏',
    onTap: () => _setFavorite(context, ref, item, true, serverId: serverId),
  );
}

/// 已观看项：已观看 → 「取消已观看」，否则 → 「标记已观看」。
GlassMenuAction _watchedAction(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  String? serverId,
}) {
  if (_effectiveWatched(ref, item)) {
    return GlassMenuAction(
      icon: Icons.visibility_off_outlined,
      label: '取消已观看',
      onTap: () => _setWatched(context, ref, item, false, serverId: serverId),
    );
  }
  return GlassMenuAction(
    icon: Icons.visibility_outlined,
    label: '标记已观看',
    onTap: () => _setWatched(context, ref, item, true, serverId: serverId),
  );
}

/// 有效收藏态：菜单乐观覆盖值优先于列表快照。
bool _effectiveFavorite(WidgetRef ref, MediaItem item) =>
    ref.read(mediaStateOverrideProvider)[item.id]?.favorite ?? item.isFavorite;

/// 有效已观看态：菜单乐观覆盖值优先于列表快照。
bool _effectiveWatched(WidgetRef ref, MediaItem item) =>
    ref.read(mediaStateOverrideProvider)[item.id]?.watched ?? item.isWatched;

Future<void> _setWatched(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  bool watched, {
  String? serverId,
}) async {
  final ok = await ref
      .read(embyServiceForProvider(serverId))
      .setWatched(item.id, watched);
  if (ok) {
    ref.read(mediaStateOverrideProvider.notifier).setWatched(item.id, watched);
    // 标记已看会让 Emby 清除续播位置：先乐观隐藏，首页立即联动。
    if (watched) {
      final hidden = ref.read(resumeOptimisticHiddenProvider.notifier);
      if (!hidden.state.contains(item.id)) {
        hidden.state = {...hidden.state, item.id};
      }
    }
    ref.read(resumeRevisionProvider.notifier).state++;
    return;
  }
  if (context.mounted) showAppToast(context, '操作失败，请检查网络');
}

Future<void> _setFavorite(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  bool favorite, {
  String? serverId,
}) async {
  final ok = await ref
      .read(embyServiceForProvider(serverId))
      .setFavorite(item.id, favorite);
  if (ok) {
    ref
        .read(mediaStateOverrideProvider.notifier)
        .setFavorite(item.id, favorite);
    ref.read(favoritesRevisionProvider.notifier).state++;
    return;
  }
  if (context.mounted) showAppToast(context, '操作失败，请检查网络');
}

Future<void> _removeFromResume(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  String? serverId,
}) async {
  final notifier = ref.read(resumeOptimisticHiddenProvider.notifier);
  if (!notifier.state.contains(item.id)) {
    notifier.state = {...notifier.state, item.id};
  }
  ref.read(resumeRevisionProvider.notifier).state++;

  final configs = <String, EmbyServerConfig>{};
  final current = ref.read(embyConfigProvider);
  if (current != null) configs[current.id] = current;
  for (final server in ref.read(embyServerListProvider)) {
    configs[server.id] = server;
  }
  final servers =
      configs.values.where((server) => server.isAuthenticated).toList();
  final sourceId = serverId?.isNotEmpty == true
      ? serverId!
      : (current?.id ?? (servers.isEmpty ? '' : servers.first.id));
  var sourceSucceeded = false;
  if (servers.any((server) => server.id == sourceId)) {
    final result = await ref.read(resumeHideServiceProvider).hideAcrossServers(
          item: item,
          sourceServerId: sourceId,
          servers: servers,
        );
    sourceSucceeded = result.sourceSucceeded;
  } else {
    sourceSucceeded = await ref
        .read(embyServiceForProvider(serverId))
        .removeFromResume(item.id);
  }
  if (sourceSucceeded) {
    ref.read(resumeRevisionProvider.notifier).state++;
    return;
  }
  notifier.state = {...notifier.state}..remove(item.id);
  ref.read(resumeRevisionProvider.notifier).state++;
  if (context.mounted) showAppToast(context, '移除失败，请检查网络');
}

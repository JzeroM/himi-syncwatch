import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 长按菜单对条目媒体状态的乐观覆盖：`itemId → (收藏?, 已观看?)`。
///
/// 列表（首页分类 / 分类页）是一次性拉取的快照，不随收藏/已看修订号重取，
/// 菜单若只看 `MediaItem.isFavorite/isWatched` 会回显旧状态。此覆盖在用户
/// 从菜单操作成功后写入，菜单读取「覆盖值 ?? 条目原值」即可即时回显最新态，
/// 无需重拉列表（与 `resumeOptimisticHiddenProvider` 同思路）。
typedef MediaStateOverride = ({bool? favorite, bool? watched});

class MediaStateOverrideNotifier
    extends StateNotifier<Map<String, MediaStateOverride>> {
  MediaStateOverrideNotifier() : super(const {});

  void setFavorite(String itemId, bool favorite) {
    final prev = state[itemId];
    state = {
      ...state,
      itemId: (favorite: favorite, watched: prev?.watched),
    };
  }

  void setWatched(String itemId, bool watched) {
    final prev = state[itemId];
    state = {
      ...state,
      itemId: (favorite: prev?.favorite, watched: watched),
    };
  }
}

final mediaStateOverrideProvider = StateNotifierProvider<
    MediaStateOverrideNotifier, Map<String, MediaStateOverride>>(
  (ref) => MediaStateOverrideNotifier(),
);

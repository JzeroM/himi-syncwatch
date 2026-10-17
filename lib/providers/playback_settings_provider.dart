import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_playback_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

/// Emby 播放阈值的只读快照：
/// - [byLibraryId]：按媒体库根条目 id（`ItemId`）→ 该库阈值。
/// - [fallback]：服务器全局阈值，作为按库缺失/解析失败时的兜底。
class PlaybackSettingsSnapshot {
  const PlaybackSettingsSnapshot({
    required this.byLibraryId,
    required this.fallback,
  });

  final Map<String, EmbyPlaybackSettings> byLibraryId;
  final EmbyPlaybackSettings fallback;

  static const PlaybackSettingsSnapshot empty = PlaybackSettingsSnapshot(
    byLibraryId: {},
    fallback: EmbyPlaybackSettings.fallback,
  );

  /// 取某库阈值；缺失回退全局。
  EmbyPlaybackSettings forLibrary(String? libraryId) {
    if (libraryId != null) {
      final s = byLibraryId[libraryId];
      if (s != null) return s;
    }
    return fallback;
  }
}

/// 每次启动（会话内首次访问）拉取一次服务器「按库 + 全局」播放阈值；
/// 不持久化，配置变更（换服）时自动失效重取。key = 服务器配置 id（null=激活）。
final playbackSettingsProvider =
    FutureProvider.family<PlaybackSettingsSnapshot, String?>(
        (ref, serverId) async {
  final config = ref.watch(embyConfigForProvider(serverId));
  if (config == null || !config.isAuthenticated) {
    return PlaybackSettingsSnapshot.empty;
  }
  final service = ref.watch(embyServiceForProvider(serverId));
  final libs = await service.getLibraryPlaybackSettings();
  final global = await service.getGlobalPlaybackSettings();
  return PlaybackSettingsSnapshot(byLibraryId: libs, fallback: global);
});

/// 条目播放阈值查询键（记录类型：值相等，可安全用于 family）。
typedef ItemPlaybackKey = ({String? serverId, String id, String? parentId});

/// 按条目解析其所属媒体库的播放阈值（带祖先兜底 + 会话内缓存）。
/// 先由 `ParentId` 命中库根；未命中且存在按库设置时，用 `Ancestors`
/// 找到所属库；仍不可得则回退全局。
final itemPlaybackSettingsProvider =
    FutureProvider.family<EmbyPlaybackSettings, ItemPlaybackKey>(
        (ref, key) async {
  PlaybackSettingsSnapshot snapshot;
  try {
    snapshot = await ref.watch(playbackSettingsProvider(key.serverId).future);
  } catch (_) {
    return EmbyPlaybackSettings.fallback;
  }
  if (snapshot.byLibraryId.isEmpty) return snapshot.fallback;

  String? libId =
      snapshot.byLibraryId.containsKey(key.parentId) ? key.parentId : null;
  if (libId == null) {
    final service = ref.watch(embyServiceForProvider(key.serverId));
    final ancestors = await service.getAncestorIds(key.id);
    for (final a in ancestors) {
      if (snapshot.byLibraryId.containsKey(a)) {
        libId = a;
        break;
      }
    }
  }
  return snapshot.forLibrary(libId);
});

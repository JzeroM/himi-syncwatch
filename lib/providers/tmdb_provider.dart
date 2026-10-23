import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

/// TMDB 客户端；未配置凭据时为 null。
final tmdbServiceProvider = Provider<TmdbService?>((ref) {
  final settings = ref.watch(
    settingsProvider.select(
      (s) => (
        s.hasTmdbCredentials,
        s.effectiveTmdbApiBase,
        s.tmdbApiKey,
      ),
    ),
  );
  if (!settings.$1) return null;
  return TmdbService(
    apiBase: settings.$2,
    credential: settings.$3,
  );
});

/// TMDB × Emby 聚合服务；未配置凭据时为 null。
final tmdbAggregateServiceProvider = Provider<TmdbAggregateService?>((ref) {
  final tmdb = ref.watch(tmdbServiceProvider);
  if (tmdb == null) return null;
  return TmdbAggregateService(
    tmdb: tmdb,
    serviceFactory: ref.watch(embyServiceFactoryProvider),
  );
});

/// 平台卡服务器海报反查状态。
class TmdbPlatformAvailabilityState {
  const TmdbPlatformAvailabilityState({
    this.entries = const {},
    required this.complete,
  });

  final Map<String, TmdbAvailability> entries;

  /// 是否已经查完全部服务器；false 时没有匹配也不能回退 TMDB。
  final bool complete;
}

List<EmbyServerConfig> _primaryServers(
  List<EmbyServerConfig> servers,
  String? activeId,
) {
  final authenticated =
      servers.where((s) => s.isAuthenticated).toList(growable: false);
  if (authenticated.isEmpty) return const [];
  if (activeId != null && activeId.isNotEmpty) {
    for (final server in authenticated) {
      if (server.id == activeId) return [server];
    }
  }
  return [authenticated.first];
}

/// TMDB 图片基地址。
final tmdbImageBaseProvider = Provider<String>((ref) {
  return ref.watch(
    settingsProvider.select((s) => s.effectiveTmdbImageBase),
  );
});

final tmdbHomeRandomSeedProvider = Provider<int>((ref) {
  return Random().nextInt(0x7FFFFFFF);
});

final tmdbHomeRefreshEpochProvider = StateProvider<int>((ref) => 0);

/// 当前 TMDB 聚合首页栏目数据。
///
/// 先立即产出首页壳（平台栏/续播区可先显示），再按各栏目实际完成顺序
/// 逐步追加，避免四个栏目 + 服务器探测全部完成后才出现首屏。
final tmdbHomeProvider = StreamProvider<TmdbHomeData>((ref) async* {
  const sectionKeys = TmdbAggregateService.homeSectionKeys;
  final configured = ref.watch(
    settingsProvider.select((s) => s.hasTmdbCredentials),
  );
  if (!configured) {
    yield const TmdbHomeData.unconfigured();
    return;
  }
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) {
    yield const TmdbHomeData.unconfigured();
    return;
  }
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  final primary = _primaryServers(servers, activeId);
  final initialServers = primary.isEmpty ? servers : primary;
  final authenticatedCount = servers.where((s) => s.isAuthenticated).length;
  final hasSecondary = primary.isNotEmpty && authenticatedCount > 1;

  var disposed = false;
  ref.onDispose(() => disposed = true);

  final failed = <String>{};
  final loaded = <String, TmdbSectionData>{};
  TmdbHomeData snapshot({required bool loading}) => TmdbHomeData(
        configured: true,
        sections: [
          for (final key in sectionKeys)
            if (loaded[key] != null) loaded[key]!,
        ],
        failedServerCount: failed.length,
        sectionsLoading: loading,
      );

  yield snapshot(loading: true);

  Future<TmdbSectionData?> load(
    String key,
    List<EmbyServerConfig> targets,
  ) async {
    try {
      final result = await service.fetchSection(
        key,
        targets,
        activeServerId: activeId,
        pages: 1,
      );
      failed.addAll(result.failedServerIds);
      return TmdbSectionData(
        key: key,
        title: TmdbAggregateService.sectionTitle(key),
        items: result.items,
      );
    } catch (_) {
      return null;
    }
  }

  var pending = <(String, Future<TmdbSectionData?>)>[
    for (final key in sectionKeys) (key, load(key, initialServers)),
  ];
  while (pending.isNotEmpty) {
    final done = await Future.any([
      for (final entry in pending)
        entry.$2.then((section) => (entry.$1, section)),
    ]);
    pending.removeWhere((entry) => entry.$1 == done.$1);
    if (disposed) return;
    final section = done.$2;
    if (section != null) loaded[section.key] = section;
    yield snapshot(loading: true);
  }

  if (disposed) return;
  final hasInitialContent = loaded.values.any((s) => s.items.isNotEmpty);
  yield snapshot(loading: hasInitialContent ? false : hasSecondary);
  if (!hasSecondary) return;

  pending = [
    for (final key in sectionKeys) (key, load(key, servers)),
  ];
  while (pending.isNotEmpty) {
    final done = await Future.any([
      for (final entry in pending)
        entry.$2.then((section) => (entry.$1, section)),
    ]);
    pending.removeWhere((entry) => entry.$1 == done.$1);
    if (disposed) return;
    final section = done.$2;
    if (section != null) {
      final previous = loaded[section.key];
      if (section.items.isNotEmpty ||
          previous == null ||
          previous.items.isEmpty) {
        loaded[section.key] = section;
      }
    }
    yield snapshot(loading: false);
  }
});

final tmdbHeroItemsProvider = Provider<List<TmdbAvailability>>((ref) {
  final data = ref.watch(tmdbHomeProvider).valueOrNull;
  if (data == null || !data.configured) return const [];
  final seed = ref.watch(tmdbHomeRandomSeedProvider) ^
      ref.watch(tmdbHomeRefreshEpochProvider);
  final candidates = <TmdbAvailability>[];
  final seen = <String>{};
  for (final section in data.sections) {
    for (final entry in section.items) {
      final url = entry.item.backdropWideUrl;
      if (url == null || url.isEmpty) continue;
      if (seen.add(entry.tmdb.key)) candidates.add(entry);
    }
  }
  candidates.shuffle(Random(seed));
  return candidates.take(6).toList(growable: false);
});

/// 光盘栏目数据。
///
/// 分区数量由 [TmdbAggregateService.discSectionKeys] 决定，UI 不写死 5 个。
/// 先当前服务器、再全服务器两阶段补齐；某分区补齐为空时不回退已有内容。
final tmdbDiscProvider = StreamProvider<TmdbDiscData>((ref) async* {
  const sectionKeys = TmdbAggregateService.discSectionKeys;
  final configured = ref.watch(
    settingsProvider.select((s) => s.hasTmdbCredentials),
  );
  if (!configured) {
    yield const TmdbDiscData.unconfigured();
    return;
  }
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) {
    yield const TmdbDiscData.unconfigured();
    return;
  }
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  final primary = _primaryServers(servers, activeId);
  final initialServers = primary.isEmpty ? servers : primary;
  final authenticatedCount = servers.where((s) => s.isAuthenticated).length;
  final hasSecondary = primary.isNotEmpty && authenticatedCount > 1;

  var disposed = false;
  ref.onDispose(() => disposed = true);

  final loaded = <String, TmdbDiscSectionData>{};
  TmdbDiscData snapshot({required bool loading}) => TmdbDiscData(
        configured: true,
        loading: loading,
        sections: [
          for (final key in sectionKeys)
            loaded[key] ??
                TmdbDiscSectionData(
                  key: key,
                  title: TmdbAggregateService.sectionTitle(key),
                  loading: true,
                ),
        ],
      );

  yield snapshot(loading: true);

  Future<TmdbDiscSectionData> load(
    String key,
    List<EmbyServerConfig> targets,
  ) async {
    try {
      final result = await service.fetchSection(
        key,
        targets,
        activeServerId: activeId,
        pages: 1,
      );
      return TmdbDiscSectionData(
        key: key,
        title: TmdbAggregateService.sectionTitle(key),
        items: result.items,
      );
    } catch (_) {
      return TmdbDiscSectionData(
        key: key,
        title: TmdbAggregateService.sectionTitle(key),
      );
    }
  }

  var pending = <(String, Future<TmdbDiscSectionData>)>[
    for (final key in sectionKeys) (key, load(key, initialServers)),
  ];
  while (pending.isNotEmpty) {
    final done = await Future.any([
      for (final entry in pending)
        entry.$2.then((section) => (entry.$1, section)),
    ]);
    pending.removeWhere((entry) => entry.$1 == done.$1);
    if (disposed) return;
    loaded[done.$1] = done.$2;
    yield snapshot(loading: true);
  }

  if (disposed) return;
  yield snapshot(loading: hasSecondary);
  if (!hasSecondary) return;

  pending = [
    for (final key in sectionKeys) (key, load(key, servers)),
  ];
  while (pending.isNotEmpty) {
    final done = await Future.any([
      for (final entry in pending)
        entry.$2.then((section) => (entry.$1, section)),
    ]);
    pending.removeWhere((entry) => entry.$1 == done.$1);
    if (disposed) return;
    final previous = loaded[done.$1];
    if (done.$2.items.isNotEmpty ||
        previous == null ||
        previous.items.isEmpty) {
      loaded[done.$1] = done.$2;
    }
    yield snapshot(loading: true);
  }

  if (disposed) return;
  yield snapshot(loading: false);
});

/// 单个平台卡的每日海报（只取 TMDB 目录，不加载 TMDB 图片）。
final tmdbPlatformShowcaseProvider =
    FutureProvider.family<TmdbPlatformShowcase, TmdbPlatform>(
  (ref, platform) async {
    final settings = ref.watch(
      settingsProvider.select(
        (s) => (s.hasTmdbCredentials, s.tmdbWatchRegion),
      ),
    );
    if (!settings.$1) return TmdbPlatformShowcase(platform: platform);
    final service = ref.watch(tmdbAggregateServiceProvider);
    if (service == null) return TmdbPlatformShowcase(platform: platform);
    return service.fetchPlatformShowcase(
      platform,
      region: settings.$2,
    );
  },
);

/// 平台卡服务器实图补齐；先当前服务器，再后台补齐其他服务器。
final tmdbPlatformAvailabilityProvider =
    StreamProvider.family<TmdbPlatformAvailabilityState, TmdbPlatform>(
  (ref, platform) async* {
    final configured =
        ref.watch(settingsProvider.select((s) => s.hasTmdbCredentials));
    if (!configured) {
      yield const TmdbPlatformAvailabilityState(complete: true);
      return;
    }
    final service = ref.watch(tmdbAggregateServiceProvider);
    if (service == null) {
      yield const TmdbPlatformAvailabilityState(complete: true);
      return;
    }
    final servers = ref.watch(embyServerListProvider);
    final activeId = ref.watch(embyConfigProvider)?.id;
    final primary = _primaryServers(servers, activeId);
    final initialServers = primary.isEmpty ? servers : primary;
    final authenticatedCount = servers.where((s) => s.isAuthenticated).length;
    final hasSecondary = primary.isNotEmpty && authenticatedCount > 1;
    final showcase =
        await ref.watch(tmdbPlatformShowcaseProvider(platform).future);

    var entries = const <String, TmdbAvailability>{};
    try {
      entries = await service.resolvePlatformShowcase(
        showcase,
        initialServers,
        activeServerId: activeId,
      );
    } catch (_) {}
    yield TmdbPlatformAvailabilityState(
      entries: entries,
      complete: !hasSecondary,
    );
    if (!hasSecondary) return;

    try {
      final full = await service.resolvePlatformShowcase(
        showcase,
        servers,
        activeServerId: activeId,
      );
      yield TmdbPlatformAvailabilityState(
        entries: {...entries, ...full},
        complete: true,
      );
    } catch (_) {
      yield TmdbPlatformAvailabilityState(entries: entries, complete: true);
    }
  },
);

/// 跨服务器继续观看。
final tmdbResumeProvider = FutureProvider<TmdbResumeResult>((ref) async {
  final settings =
      ref.watch(settingsProvider.select((s) => s.hasTmdbCredentials));
  if (!settings) {
    return const TmdbResumeResult(entries: []);
  }
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) return const TmdbResumeResult(entries: []);
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  ref.watch(resumeRevisionProvider);
  final hidden = ref.watch(resumeOptimisticHiddenProvider);
  final result = await service.fetchResume(
    servers,
    activeId,
  );
  if (hidden.isEmpty) return result;
  return TmdbResumeResult(
    entries: [
      for (final entry in result.entries)
        if (!hidden.contains(entry.item.id)) entry,
    ],
    failedServerIds: result.failedServerIds,
  );
});

Future<void> refreshTmdbHome(WidgetRef ref) async {
  ref.read(tmdbHomeRefreshEpochProvider.notifier).state++;
  ref.invalidate(tmdbHomeProvider);
  ref.invalidate(tmdbResumeProvider);
  ref.invalidate(tmdbDiscProvider);
  ref.invalidate(tmdbPlatformShowcaseProvider);
  ref.invalidate(tmdbPlatformAvailabilityProvider);
  for (final future in [
    ref.read(tmdbHomeProvider.future),
    ref.read(tmdbResumeProvider.future),
  ]) {
    try {
      await future;
    } catch (_) {}
  }
}

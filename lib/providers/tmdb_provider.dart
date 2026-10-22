import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
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

/// TMDB 图片基地址。
final tmdbImageBaseProvider = Provider<String>((ref) {
  return ref.watch(
    settingsProvider.select((s) => s.effectiveTmdbImageBase),
  );
});

/// 当前 TMDB 聚合首页栏目数据。
///
/// 先立即产出首页壳（平台栏/续播区可先显示），再按各栏目实际完成顺序
/// 逐步追加，避免四个栏目 + 服务器探测全部完成后才出现首屏。
final tmdbHomeProvider = StreamProvider<TmdbHomeData>((ref) async* {
  const sectionKeys = [
    'trending_day',
    'trending_week',
    'popular_movies',
    'popular_tv',
  ];
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

  Future<TmdbSectionData?> load(String key) async {
    try {
      final result = await service.fetchSection(
        key,
        servers,
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

  final pending = <(String, Future<TmdbSectionData?>)>[
    for (final key in sectionKeys) (key, load(key)),
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
  yield snapshot(loading: false);
});

/// 单个平台卡的每日海报（先只取 TMDB 图，尽快显示）。
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

/// 平台卡服务器实图补齐；不阻塞 TMDB 海报首帧。
final tmdbPlatformAvailabilityProvider =
    FutureProvider.family<Map<String, TmdbAvailability>, TmdbPlatform>(
  (ref, platform) async {
    final configured =
        ref.watch(settingsProvider.select((s) => s.hasTmdbCredentials));
    if (!configured) return const {};
    final service = ref.watch(tmdbAggregateServiceProvider);
    if (service == null) return const {};
    final servers = ref.watch(embyServerListProvider);
    final activeId = ref.watch(embyConfigProvider)?.id;
    final showcase =
        await ref.watch(tmdbPlatformShowcaseProvider(platform).future);
    return service.resolvePlatformShowcase(
      showcase,
      servers,
      activeServerId: activeId,
    );
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
  return service.fetchResume(
    servers,
    activeId,
  );
});

Future<void> refreshTmdbHome(WidgetRef ref) async {
  ref.invalidate(tmdbHomeProvider);
  ref.invalidate(tmdbResumeProvider);
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

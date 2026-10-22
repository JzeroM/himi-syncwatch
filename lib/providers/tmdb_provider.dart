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
final tmdbHomeProvider = FutureProvider<TmdbHomeData>((ref) async {
  final settings =
      ref.watch(settingsProvider.select((s) => s.hasTmdbCredentials));
  if (!settings) {
    return const TmdbHomeData.unconfigured();
  }
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) return const TmdbHomeData.unconfigured();
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  return service.fetchSections(
    servers,
    activeServerId: activeId,
  );
});

/// 首页流媒体平台卡的每日随机海报。
final tmdbPlatformShowcasesProvider =
    FutureProvider<List<TmdbPlatformShowcase>>((ref) async {
  List<TmdbPlatformShowcase> empty() => [
        for (final platform in tmdbPlatforms)
          TmdbPlatformShowcase(platform: platform),
      ];
  final settings = ref.watch(
    settingsProvider.select(
      (s) => (s.hasTmdbCredentials, s.tmdbWatchRegion),
    ),
  );
  if (!settings.$1) return empty();
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) return empty();
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  return service.fetchPlatformShowcases(
    servers,
    region: settings.$2,
    activeServerId: activeId,
  );
});

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
  ref.invalidate(tmdbPlatformShowcasesProvider);
  for (final future in [
    ref.read(tmdbHomeProvider.future),
    ref.read(tmdbResumeProvider.future),
  ]) {
    try {
      await future;
    } catch (_) {}
  }
}

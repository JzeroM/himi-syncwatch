import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

/// TMDB 客户端；未配置凭据时为 null。
final tmdbServiceProvider = Provider<TmdbService?>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.hasTmdbCredentials) return null;
  return TmdbService(
    apiBase: settings.effectiveTmdbApiBase,
    credential: settings.tmdbApiKey,
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
  return ref.watch(settingsProvider).effectiveTmdbImageBase;
});

/// 当前 TMDB 聚合首页数据。
final tmdbHomeProvider = FutureProvider.autoDispose<TmdbHomeData>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (!settings.hasTmdbCredentials) {
    return const TmdbHomeData.unconfigured();
  }
  final service = ref.watch(tmdbAggregateServiceProvider);
  if (service == null) return const TmdbHomeData.unconfigured();
  final servers = ref.watch(embyServerListProvider);
  final activeId = ref.watch(embyConfigProvider)?.id;
  return service.fetchHome(
    servers,
    activeServerId: activeId,
    region: settings.tmdbWatchRegion,
  );
});

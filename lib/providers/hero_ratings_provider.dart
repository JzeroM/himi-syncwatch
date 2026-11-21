import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:himi_syncwatch/services/ratings_cache_store.dart';

/// 评分徽章持久缓存（698 N7-I）：无依赖 Provider——服务随 settings/trakt
/// 重建时缓存**不随之清零**（旧「重复获取」真凶之一）；跨启动同样命中。
final ratingsCacheStoreProvider = Provider<RatingsCacheStore>((ref) {
  return SecureRatingsCacheStore();
});

/// 多平台评分服务（698）：拼装 OMDb key 与 Trakt 评分桥。
///
/// - OMDb：key 来自设置（可选，留空走内置免费 key）；豆瓣/Letterboxd 走
///   免 key 爬页（服务内自行处理）；
/// - Trakt：走仓内已有 Trakt 集成——**已登录**才注入评分桥（连账号即亮），
///   未登录时该源跳过；条目缓存走 [ratingsCacheStoreProvider]（会话 + 持久）。
final heroRatingsServiceProvider = Provider<HeroRatingsService>((ref) {
  final omdbApiKey = ref.watch(
    settingsProvider.select((s) => s.omdbApiKey),
  );
  final trakt = ref.watch(traktClientProvider);
  return HeroRatingsService(
    omdbApiKey: omdbApiKey,
    cacheStore: ref.watch(ratingsCacheStoreProvider),
    // OMDb 免费 key 串行限速（698 N7-F：仅 OMDb 过队列，爬页源并行）。
    queueGap: const Duration(milliseconds: 60),
    // 登录态运行时可变（登录后即亮），判据放调用时而非构建时。
    traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
      if (!trakt.isAuthenticated) return Future<double?>.value();
      return trakt.getRating(
        imdbId: imdbId,
        tmdbId: tmdbId,
        isMovie: isMovie,
      );
    },
  );
});

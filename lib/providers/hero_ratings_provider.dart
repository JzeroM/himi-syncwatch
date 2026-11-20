import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';

/// 多平台评分服务（698）：拼装 OMDb / MDBList key 与 Trakt 评分桥。
///
/// - OMDb / MDBList：key 来自设置（可选，缺则对应源静默跳过）；
/// - Trakt：走仓内已有 Trakt 集成——**已登录**才注入评分桥（连账号即亮），
///   未登录时该源跳过；条目缓存在 service 实例内。
final heroRatingsServiceProvider = Provider<HeroRatingsService>((ref) {
  final omdbApiKey = ref.watch(
    settingsProvider.select((s) => s.omdbApiKey),
  );
  final mdblistApiKey = ref.watch(
    settingsProvider.select((s) => s.mdblistApiKey),
  );
  final trakt = ref.watch(traktClientProvider);
  return HeroRatingsService(
    omdbApiKey: omdbApiKey,
    mdblistApiKey: mdblistApiKey,
    // 生产请求串行 + 抖动间隔，避开免费 key 并发限速（698）。
    queueGap: const Duration(milliseconds: 150),
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

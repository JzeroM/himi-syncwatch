import 'package:himi_syncwatch/models/tmdb_item.dart';

/// 固定展示的流媒体平台（TMDB watch provider id）。
class TmdbPlatform {
  const TmdbPlatform({
    required this.providerId,
    required this.name,
    required this.logoAsset,
    this.logoHeight = 20,
  });

  final int providerId;
  final String name;
  final String logoAsset;
  final double logoHeight;
}

const List<TmdbPlatform> tmdbPlatforms = [
  TmdbPlatform(
    providerId: 8,
    name: 'Netflix',
    logoAsset: 'assets/images/platforms/netflix.png',
  ),
  TmdbPlatform(
    providerId: 337,
    name: 'Disney+',
    logoAsset: 'assets/images/platforms/disney_plus.png',
    logoHeight: 24,
  ),
  TmdbPlatform(
    providerId: 350,
    name: 'Apple TV+',
    logoAsset: 'assets/images/platforms/apple_tv_plus.png',
  ),
  TmdbPlatform(
    providerId: 1899,
    name: 'HBO Max',
    logoAsset: 'assets/images/platforms/hbo_max.png',
  ),
  TmdbPlatform(
    providerId: 15,
    name: 'Hulu',
    logoAsset: 'assets/images/platforms/hulu.png',
  ),
  TmdbPlatform(
    providerId: 9,
    name: 'Prime Video',
    logoAsset: 'assets/images/platforms/prime_video.png',
  ),
  TmdbPlatform(
    providerId: 531,
    name: 'Paramount+',
    logoAsset: 'assets/images/platforms/paramount_plus.png',
  ),
];

TmdbPlatform? tmdbPlatformById(int providerId) {
  for (final p in tmdbPlatforms) {
    if (p.providerId == providerId) return p;
  }
  return null;
}

String? tmdbPlatformName(int providerId) {
  return tmdbPlatformById(providerId)?.name;
}

/// 平台卡片展示的海报（服务器实图优先，TMDB 图兜底）。
class TmdbPlatformPoster {
  const TmdbPlatformPoster({
    required this.tmdb,
    this.availability,
  });

  final TmdbItem tmdb;
  final TmdbAvailability? availability;

  bool get hasServerPoster => availability != null;
}

/// 单个流媒体平台的每日展示数据。
class TmdbPlatformShowcase {
  const TmdbPlatformShowcase({
    required this.platform,
    this.posters = const [],
  });

  final TmdbPlatform platform;
  final List<TmdbPlatformPoster> posters;
}

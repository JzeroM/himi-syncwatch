/// 固定展示的流媒体平台（TMDB watch provider id）。
class TmdbPlatform {
  const TmdbPlatform({
    required this.providerId,
    required this.name,
    required this.logoAsset,
  });

  final int providerId;
  final String name;
  final String logoAsset;
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

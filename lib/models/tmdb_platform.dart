/// 固定展示的流媒体平台（TMDB watch provider id）。
class TmdbPlatform {
  const TmdbPlatform({required this.providerId, required this.name});

  final int providerId;
  final String name;
}

const List<TmdbPlatform> tmdbPlatforms = [
  TmdbPlatform(providerId: 8, name: 'Netflix'),
  TmdbPlatform(providerId: 337, name: 'Disney+'),
  TmdbPlatform(providerId: 350, name: 'Apple TV+'),
  TmdbPlatform(providerId: 1899, name: 'HBO Max'),
  TmdbPlatform(providerId: 15, name: 'Hulu'),
  TmdbPlatform(providerId: 531, name: 'Paramount+'),
];

String? tmdbPlatformName(int providerId) {
  for (final p in tmdbPlatforms) {
    if (p.providerId == providerId) return p.name;
  }
  return null;
}

import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

class TraktItemLocator {
  static const _fields = 'ProviderIds,UserData,RunTimeTicks,SeriesId,'
      'IndexNumber,ParentIndexNumber';

  const TraktItemLocator();

  Future<List<MediaItem>> findMovies(
    EmbyService service,
    TraktMediaIds ids,
  ) async {
    final tokens = providerTokens(ids);
    if (tokens.isEmpty) return const [];
    final items = await _query(
      service,
      includeItemTypes: 'Movie',
      anyProviderIds: tokens,
    );
    return items
        .where((e) => e.isMovie && _matches(e, tokens))
        .toList(growable: false);
  }

  Future<List<MediaItem>> findEpisodes(
    EmbyService service, {
    required TraktMediaIds showIds,
    required int season,
    required int episode,
    TraktMediaIds episodeIds = const TraktMediaIds(),
  }) async {
    final result = <String, MediaItem>{};
    final episodeTokens = providerTokens(episodeIds);
    if (episodeTokens.isNotEmpty) {
      final direct = await _query(
        service,
        includeItemTypes: 'Episode',
        anyProviderIds: episodeTokens,
      );
      for (final item in direct) {
        if (!_matches(item, episodeTokens)) continue;
        if (!_episodeMatches(item, season, episode)) continue;
        result[item.id] = item;
      }
    }

    final showTokens = providerTokens(showIds);
    if (showTokens.isNotEmpty) {
      final series = await _query(
        service,
        includeItemTypes: 'Series',
        anyProviderIds: showTokens,
        fields: 'ProviderIds',
      );
      for (final show in series.where((e) => e.isSeries)) {
        if (!_matches(show, showTokens)) continue;
        final episodes = await _query(
          service,
          parentId: show.id,
          includeItemTypes: 'Episode',
        );
        for (final item in episodes) {
          if (!_episodeMatches(item, season, episode)) continue;
          result[item.id] = item;
        }
      }
    }

    return result.values.toList(growable: false);
  }

  List<String> providerTokens(TraktMediaIds ids) {
    final tokens = <String>[];
    if (ids.tmdb != null && ids.tmdb! > 0) tokens.add('tmdb.${ids.tmdb}');
    if (ids.tvdb != null && ids.tvdb! > 0) tokens.add('tvdb.${ids.tvdb}');
    final imdb = ids.imdb?.trim().toLowerCase() ?? '';
    if (imdb.isNotEmpty) tokens.add('imdb.$imdb');
    return tokens;
  }

  Future<List<MediaItem>> _query(
    EmbyService service, {
    String? includeItemTypes,
    String? parentId,
    List<String>? anyProviderIds,
    String fields = _fields,
  }) async {
    final result = <MediaItem>[];
    var start = 0;
    const pageSize = 500;
    String? previousFirst;
    for (var page = 0; page < 1000; page++) {
      final chunk = await service.getItems(
        includeItemTypes: includeItemTypes,
        parentId: parentId,
        anyProviderIds: anyProviderIds,
        fields: fields,
        limit: pageSize,
        startIndex: start,
      );
      if (chunk.isEmpty) break;
      if (chunk.first.id == previousFirst) break;
      previousFirst = chunk.first.id;
      result.addAll(chunk);
      start += chunk.length;
    }
    return result;
  }

  bool _matches(MediaItem item, List<String> tokens) {
    final itemTokens = providerTokens(TraktMediaIds(
      tmdb: int.tryParse(item.providerId('tmdb') ?? ''),
      tvdb: int.tryParse(item.providerId('tvdb') ?? ''),
      imdb: item.providerId('imdb'),
    ));
    return itemTokens.any(tokens.contains);
  }

  bool _episodeMatches(MediaItem item, int season, int episode) {
    return item.isEpisode &&
        item.parentIndexNumber == season &&
        item.indexNumber == episode;
  }
}

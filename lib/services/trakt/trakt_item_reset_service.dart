import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_item_locator.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';

class TraktItemResetService {
  final TraktClient client;
  final TraktItemLocator locator;

  const TraktItemResetService({
    required this.client,
    this.locator = const TraktItemLocator(),
  });

  Future<bool> resetItem({
    required List<TraktServerHandle> servers,
    required String serverConfigId,
    required String itemId,
    required bool removeWatched,
  }) async {
    final origin = _findServer(servers, serverConfigId);
    if (origin == null) return false;
    final item = await origin.service.getItemDetails(itemId);
    if (item == null) return false;
    final target = await _targetFor(origin.service, item);
    if (target == null) return false;

    await _deletePlayback(target);
    if (removeWatched) {
      await _removeHistory(target);
    }

    for (final server in servers) {
      if (server.configId == origin.configId) continue;
      try {
        final locals = await _findLocal(server, target);
        for (final local in locals) {
          if (removeWatched) {
            await server.service.setWatched(local.id, false);
          }
          await server.service.setPlaybackPosition(local.id, 0);
        }
      } catch (_) {}
    }
    return true;
  }

  TraktServerHandle? _findServer(
    List<TraktServerHandle> servers,
    String configId,
  ) {
    for (final server in servers) {
      if (configId.isEmpty || server.configId == configId) return server;
    }
    return servers.isEmpty ? null : servers.first;
  }

  Future<_ResetTarget?> _targetFor(
    EmbyService service,
    MediaItem item,
  ) async {
    if (item.isMovie) {
      return _ResetTarget(
        kind: TraktItemKind.movie,
        ids: _idsFromMedia(item),
      );
    }
    if (!item.isEpisode) return null;
    final season = item.parentIndexNumber;
    final episode = item.indexNumber;
    if (season == null || episode == null) return null;
    var showIds = const TraktMediaIds();
    final seriesId = item.seriesId;
    if (seriesId != null) {
      final series = await service.getItemDetails(seriesId);
      if (series != null) showIds = _idsFromMedia(series);
    }
    return _ResetTarget(
      kind: TraktItemKind.episode,
      ids: _idsFromMedia(item),
      showIds: showIds,
      season: season,
      episode: episode,
    );
  }

  Future<List<MediaItem>> _findLocal(
    TraktServerHandle server,
    _ResetTarget target,
  ) {
    if (target.kind == TraktItemKind.movie) {
      return locator.findMovies(server.service, target.ids);
    }
    return locator.findEpisodes(
      server.service,
      showIds: target.showIds,
      season: target.season ?? 0,
      episode: target.episode ?? 0,
      episodeIds: target.ids,
    );
  }

  Future<void> _deletePlayback(_ResetTarget target) async {
    try {
      final rows = await client.getPlayback();
      for (final row in rows) {
        if (!_matchesPlayback(row, target)) continue;
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        await client.deletePlayback(id);
      }
    } catch (_) {}
  }

  bool _matchesPlayback(Map<String, dynamic> row, _ResetTarget target) {
    if (target.kind == TraktItemKind.movie) {
      final movie = row['movie'];
      if (movie is! Map) return false;
      final ids = _idsFromMap(movie['ids']);
      return _overlaps(ids, target.ids);
    }
    final episode = row['episode'];
    if (episode is! Map) return false;
    if ((episode['season'] as num?)?.toInt() != target.season) return false;
    if ((episode['number'] as num?)?.toInt() != target.episode) return false;
    final episodeIds = _idsFromMap(episode['ids']);
    if (_overlaps(episodeIds, target.ids)) return true;
    final show = row['show'];
    if (show is! Map) return false;
    return _overlaps(_idsFromMap(show['ids']), target.showIds);
  }

  Future<void> _removeHistory(_ResetTarget target) async {
    try {
      if (target.kind == TraktItemKind.movie) {
        if (!_hasIds(target.ids)) return;
        await client.removeHistory(movies: [
          {'ids': target.ids.toJson()},
        ]);
        return;
      }
      if (!_hasIds(target.showIds) ||
          target.season == null ||
          target.episode == null) {
        return;
      }
      await client.removeHistory(shows: [
        {
          'ids': target.showIds.toJson(),
          'seasons': [
            {
              'number': target.season,
              'episodes': [
                {'number': target.episode},
              ],
            },
          ],
        },
      ]);
    } catch (_) {}
  }

  bool _overlaps(TraktMediaIds a, TraktMediaIds b) {
    if (a.trakt != null && b.trakt != null && a.trakt == b.trakt) return true;
    if (a.tmdb != null && b.tmdb != null && a.tmdb == b.tmdb) return true;
    if (a.tvdb != null && b.tvdb != null && a.tvdb == b.tvdb) return true;
    final ai = a.imdb?.trim().toLowerCase();
    final bi = b.imdb?.trim().toLowerCase();
    return ai != null && ai.isNotEmpty && ai == bi;
  }

  TraktMediaIds _idsFromMedia(MediaItem item) {
    return TraktMediaIds(
      tmdb: int.tryParse(item.providerId('tmdb') ?? ''),
      tvdb: int.tryParse(item.providerId('tvdb') ?? ''),
      imdb: item.providerId('imdb'),
    );
  }

  TraktMediaIds _idsFromMap(Object? raw) {
    if (raw is Map<String, dynamic>) return TraktMediaIds.fromJson(raw);
    if (raw is Map) {
      return TraktMediaIds.fromJson(Map<String, dynamic>.from(raw));
    }
    return const TraktMediaIds();
  }

  bool _hasIds(TraktMediaIds ids) =>
      (ids.trakt != null && ids.trakt! > 0) ||
      (ids.tmdb != null && ids.tmdb! > 0) ||
      (ids.tvdb != null && ids.tvdb! > 0) ||
      (ids.imdb != null && ids.imdb!.trim().isNotEmpty);
}

class _ResetTarget {
  final TraktItemKind kind;
  final TraktMediaIds ids;
  final TraktMediaIds showIds;
  final int? season;
  final int? episode;

  const _ResetTarget({
    required this.kind,
    required this.ids,
    this.showIds = const TraktMediaIds(),
    this.season,
    this.episode,
  });
}

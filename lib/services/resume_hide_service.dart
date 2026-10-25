import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

class ResumeHideResult {
  final bool sourceSucceeded;
  final int hidden;

  const ResumeHideResult({
    required this.sourceSucceeded,
    required this.hidden,
  });
}

class ResumeHideService {
  final EmbyService Function(EmbyServerConfig server) serviceFactory;

  const ResumeHideService({required this.serviceFactory});

  Future<ResumeHideResult> hideAcrossServers({
    required MediaItem item,
    required String sourceServerId,
    required List<EmbyServerConfig> servers,
  }) async {
    final source = _sourceServer(servers, sourceServerId);
    if (source == null) {
      return const ResumeHideResult(sourceSucceeded: false, hidden: 0);
    }
    var sourceSucceeded = false;
    var hidden = 0;
    for (final group in _groups(servers, 3)) {
      final results = await Future.wait(group.map((server) async {
        try {
          if (server.id == source.id) {
            final ok = await serviceFactory(server).removeFromResume(item.id);
            return (source: true, ok: ok, hidden: ok ? 1 : 0);
          }
          final resume =
              await serviceFactory(server).getResumeItems(limit: 100);
          var count = 0;
          for (final candidate in resume) {
            if (!_sameItem(item, candidate)) continue;
            final ok =
                await serviceFactory(server).removeFromResume(candidate.id);
            if (ok) count++;
          }
          return (source: false, ok: true, hidden: count);
        } catch (_) {
          return (source: server.id == source.id, ok: false, hidden: 0);
        }
      }));
      for (final result in results) {
        hidden += result.hidden;
        if (result.source) sourceSucceeded = result.ok;
      }
    }
    return ResumeHideResult(sourceSucceeded: sourceSucceeded, hidden: hidden);
  }

  EmbyServerConfig? _sourceServer(
    List<EmbyServerConfig> servers,
    String sourceServerId,
  ) {
    for (final server in servers) {
      if (server.id == sourceServerId) return server;
    }
    return servers.isEmpty ? null : servers.first;
  }

  bool _sameItem(MediaItem source, MediaItem candidate) {
    if (source.isEpisode != candidate.isEpisode) return false;
    if (source.isMovie != candidate.isMovie) return false;
    final sourceTmdb = source.tmdbId;
    final candidateTmdb = candidate.tmdbId;
    if (sourceTmdb != null && candidateTmdb != null) {
      return sourceTmdb == candidateTmdb;
    }
    for (final provider in const ['imdb', 'tvdb']) {
      final a = source.providerId(provider);
      final b = candidate.providerId(provider);
      if (a != null && b != null) return a == b;
    }
    if (source.isEpisode) {
      return _normalize(source.seriesName) ==
              _normalize(candidate.seriesName) &&
          source.parentIndexNumber == candidate.parentIndexNumber &&
          source.indexNumber == candidate.indexNumber;
    }
    return _normalize(source.name) == _normalize(candidate.name) &&
        source.year == candidate.year;
  }

  String _normalize(String? value) => (value ?? '').trim().toLowerCase();

  List<List<T>> _groups<T>(List<T> values, int size) {
    final result = <List<T>>[];
    for (var start = 0; start < values.length; start += size) {
      result.add(values.sublist(
        start,
        start + size > values.length ? values.length : start + size,
      ));
    }
    return result;
  }
}

import 'dart:math' as math;

import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';

class TraktSyncPlanner {
  static const _progressEpsilonMs = 1000;
  static const _maxEmbyUnwatchedRatio = 0.89;

  const TraktSyncPlanner();

  TraktSyncPlan build({
    required List<TraktSyncEntry> local,
    required List<TraktSyncEntry> remote,
    Map<String, DateTime> resetAt = const {},
  }) {
    final actions = <TraktSyncAction>[];
    final effective = <TraktSyncEntry>[];
    for (final entry in local) {
      final stale = _isStale(entry, resetAt);
      if (stale && entry.watched) {
        actions.add(TraktSyncAction(
          type: TraktActionType.unmarkEmbyWatched,
          entry: entry,
          serverConfigId: entry.serverConfigId,
          itemId: entry.itemId,
        ));
      }
      if (stale && entry.positionMs > 0) {
        actions.add(TraktSyncAction(
          type: TraktActionType.clearEmbyProgress,
          entry: entry,
          serverConfigId: entry.serverConfigId,
          itemId: entry.itemId,
        ));
      }
      effective.add(_applyResetWatermark(entry, resetAt));
    }
    final all = [...effective, ...remote];
    if (all.isEmpty) {
      return const TraktSyncPlan(
        actions: [],
        stats: TraktSyncStatistics(),
      );
    }

    final union = _UnionFind();
    for (final entry in all) {
      union.unionAll(entry.identityTokens);
    }

    final groups = <String, _EntryGroup>{};
    for (final entry in all) {
      final tokens = entry.identityTokens;
      final root = tokens.isEmpty ? 'unknown' : union.find(tokens.first);
      var key = entry.isMovie ? 'movie|$root' : 'episode|$root';
      if (entry.isEpisode) {
        key = '$key|s${entry.season ?? 0}|e${entry.episode ?? 0}';
      }
      final group = groups.putIfAbsent(key, () => _EntryGroup(key));
      if (entry.hasLocal) {
        group.local.add(entry);
      } else {
        group.remote.add(entry);
      }
    }

    var movieCount = 0;
    var episodeCount = 0;
    final showKeys = <String>{};

    for (final group in groups.values) {
      if (group.local.isEmpty) continue;
      final matched = group.remote.isNotEmpty;
      final remoteWatched = group.remote.any((e) => e.watched);
      final localWatched = group.local.any((e) => e.watched);
      final watched = remoteWatched || localWatched;

      if (matched) {
        if (group.local.first.isMovie) {
          movieCount++;
        } else {
          episodeCount++;
          showKeys.add(_showKeyFor(group));
        }
      }

      if (watched) {
        for (final localEntry in group.local) {
          if (!localEntry.watched) {
            actions.add(TraktSyncAction(
              type: TraktActionType.markEmbyWatched,
              entry: localEntry,
              serverConfigId: localEntry.serverConfigId,
              itemId: localEntry.itemId,
            ));
          }
          if (localEntry.positionMs > 0) {
            actions.add(TraktSyncAction(
              type: TraktActionType.clearEmbyProgress,
              entry: localEntry,
              serverConfigId: localEntry.serverConfigId,
              itemId: localEntry.itemId,
            ));
          }
        }
        if (!remoteWatched) {
          final source = _historySource(group.local);
          if (source != null) {
            actions.add(TraktSyncAction(
              type: TraktActionType.addTraktHistory,
              entry: source,
            ));
          }
        }
        for (final playback in group.remote) {
          if (playback.playbackId != null) {
            actions.add(TraktSyncAction(
              type: TraktActionType.deleteTraktPlayback,
              playbackId: playback.playbackId,
            ));
          }
        }
        continue;
      }

      final bestLocal =
          group.local.map((e) => e.positionMs).fold<int>(0, math.max);
      final runtime = _runtimeFor(group);
      final bestRemote =
          group.remote.map((e) => _remoteMs(e, runtime)).fold<int>(0, math.max);
      final best = math.max(bestLocal, bestRemote);
      if (best <= 0) continue;

      for (final localEntry in group.local) {
        if (localEntry.positionMs + _progressEpsilonMs >= best) continue;
        final target = _safeEmbyProgress(localEntry, best);
        if (target <= localEntry.positionMs + _progressEpsilonMs) continue;
        actions.add(TraktSyncAction(
          type: TraktActionType.writeEmbyProgress,
          entry: localEntry,
          serverConfigId: localEntry.serverConfigId,
          itemId: localEntry.itemId,
          positionMs: target,
        ));
      }

      if (best > bestRemote + _progressEpsilonMs) {
        final source = _pauseSource(group.local, best);
        final pauseRuntime = source?.runtimeMs ?? runtime;
        if (source != null && pauseRuntime != null && pauseRuntime > 0) {
          final percent =
              (best / pauseRuntime * 100).clamp(0.1, 95.0).toDouble();
          actions.add(TraktSyncAction(
            type: TraktActionType.pauseTrakt,
            entry: source,
            positionMs: best,
            progressPercent: percent,
          ));
        }
      }
    }

    return TraktSyncPlan(
      actions: actions,
      stats: TraktSyncStatistics(
        movies: movieCount,
        shows: showKeys.length,
        episodes: episodeCount,
      ),
    );
  }

  bool _isStale(TraktSyncEntry entry, Map<String, DateTime> resetAt) {
    final serverId = entry.serverConfigId;
    if (serverId == null) return false;
    final reset = resetAt[serverId];
    if (reset == null) return false;
    final lastPlayed = entry.lastPlayed;
    return lastPlayed == null || !lastPlayed.isAfter(reset);
  }

  TraktSyncEntry _applyResetWatermark(
    TraktSyncEntry entry,
    Map<String, DateTime> resetAt,
  ) {
    if (!_isStale(entry, resetAt)) return entry;
    return TraktSyncEntry(
      kind: entry.kind,
      ids: entry.ids,
      showIds: entry.showIds,
      season: entry.season,
      episode: entry.episode,
      watched: false,
      positionMs: 0,
      progressPercent: null,
      runtimeMs: entry.runtimeMs,
      lastPlayed: entry.lastPlayed,
      serverConfigId: entry.serverConfigId,
      itemId: entry.itemId,
    );
  }

  int? _runtimeFor(_EntryGroup group) {
    final runtimes = [
      ...group.local.map((e) => e.runtimeMs),
      ...group.remote.map((e) => e.runtimeMs),
    ].whereType<int>().where((e) => e > 0).toList();
    if (runtimes.isEmpty) return null;
    runtimes.sort();
    return runtimes.last;
  }

  int _remoteMs(TraktSyncEntry entry, int? runtime) {
    final percent = entry.progressPercent;
    if (percent == null || runtime == null || runtime <= 0) {
      return entry.positionMs;
    }
    return (percent / 100 * runtime).round();
  }

  int _safeEmbyProgress(TraktSyncEntry local, int desired) {
    final runtime = local.runtimeMs;
    if (runtime == null || runtime <= 0) return desired;
    final cap = (runtime * _maxEmbyUnwatchedRatio).floor();
    return math.min(desired, math.max(0, cap));
  }

  TraktSyncEntry? _historySource(List<TraktSyncEntry> local) {
    for (final entry in local) {
      if (entry.isMovie && _hasIds(entry.ids)) return entry;
      if (entry.isEpisode &&
          _hasIds(entry.showIds) &&
          entry.season != null &&
          entry.episode != null) {
        return entry;
      }
    }
    return null;
  }

  TraktSyncEntry? _pauseSource(List<TraktSyncEntry> local, int best) {
    TraktSyncEntry? candidate;
    for (final entry in local) {
      if (entry.positionMs != best) continue;
      if (entry.isMovie && _hasIds(entry.ids)) candidate = entry;
      if (entry.isEpisode &&
          entry.season != null &&
          entry.episode != null &&
          (_hasIds(entry.ids) || _hasIds(entry.showIds))) {
        candidate = entry;
      }
      if (candidate != null) break;
    }
    if (candidate != null) return candidate;
    for (final entry in local) {
      if (entry.isMovie && _hasIds(entry.ids)) return entry;
      if (entry.isEpisode &&
          entry.season != null &&
          entry.episode != null &&
          (_hasIds(entry.ids) || _hasIds(entry.showIds))) {
        return entry;
      }
    }
    return null;
  }

  bool _hasIds(TraktMediaIds ids) =>
      (ids.trakt != null && ids.trakt! > 0) ||
      (ids.tmdb != null && ids.tmdb! > 0) ||
      (ids.tvdb != null && ids.tvdb! > 0) ||
      (ids.imdb != null && ids.imdb!.trim().isNotEmpty);

  String _showKeyFor(_EntryGroup group) {
    final keys = group.remote
        .where((e) => e.isEpisode)
        .map((e) => e.showIdentity)
        .where((k) => k != 'show:unknown')
        .toList();
    if (keys.isNotEmpty) {
      keys.sort();
      return keys.first;
    }
    final localKeys = group.local
        .where((e) => e.isEpisode)
        .map((e) => e.showIdentity)
        .where((k) => k != 'show:unknown')
        .toList();
    if (localKeys.isNotEmpty) {
      localKeys.sort();
      return localKeys.first;
    }
    return group.key;
  }
}

class _EntryGroup {
  final String key;
  final List<TraktSyncEntry> local = [];
  final List<TraktSyncEntry> remote = [];

  _EntryGroup(this.key);
}

class _UnionFind {
  final Map<String, String> _parent = {};

  String find(String value) {
    final parent = _parent[value];
    if (parent == null) {
      _parent[value] = value;
      return value;
    }
    if (parent == value) return value;
    final root = find(parent);
    _parent[value] = root;
    return root;
  }

  void unionAll(List<String> values) {
    if (values.isEmpty) return;
    final first = find(values.first);
    for (final value in values.skip(1)) {
      final root = find(value);
      if (root != first) _parent[root] = first;
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_planner.dart';

const _planner = TraktSyncPlanner();

TraktSyncEntry _movie({
  String server = 'a',
  String? item = 'm1',
  int? tmdb = 1,
  bool watched = false,
  int position = 0,
  int runtime = 100000,
  DateTime? lastPlayed,
  int? playbackId,
  double? progressPercent,
}) {
  return TraktSyncEntry(
    kind: TraktItemKind.movie,
    ids: TraktMediaIds(tmdb: tmdb),
    watched: watched,
    positionMs: position,
    progressPercent: progressPercent,
    runtimeMs: runtime,
    lastPlayed: lastPlayed,
    serverConfigId: server,
    itemId: item,
    playbackId: playbackId,
  );
}

TraktSyncEntry _episode({
  String server = 'a',
  String item = 'e1',
  int showTmdb = 10,
  int season = 1,
  int episode = 2,
  bool watched = false,
  int position = 0,
  int runtime = 100000,
  DateTime? lastPlayed,
  int? playbackId,
}) {
  return TraktSyncEntry(
    kind: TraktItemKind.episode,
    ids: const TraktMediaIds(),
    showIds: TraktMediaIds(tmdb: showTmdb),
    season: season,
    episode: episode,
    watched: watched,
    positionMs: position,
    runtimeMs: runtime,
    lastPlayed: lastPlayed,
    serverConfigId: server,
    itemId: item,
    playbackId: playbackId,
  );
}

void main() {
  test('任一服务器已看 → 其他服务器补已看且写入 Trakt 历史', () {
    final plan = _planner.build(
      local: [
        _movie(server: 'a', item: 'a1', watched: true),
        _movie(server: 'b', item: 'b1'),
      ],
      remote: const [],
    );

    expect(
      plan.actions
          .where((a) => a.type == TraktActionType.markEmbyWatched)
          .map((a) => a.itemId),
      ['b1'],
    );
    expect(
      plan.actions.where((a) => a.type == TraktActionType.addTraktHistory),
      hasLength(1),
    );
  });

  test('已看优先于进度：清进度、删 Trakt playback，不再上报进度', () {
    final plan = _planner.build(
      local: [
        _movie(server: 'a', item: 'a1', position: 50000),
      ],
      remote: [
        _movie(server: '', item: null, watched: true, playbackId: 9),
      ],
    );

    expect(
      plan.actions.where((a) => a.type == TraktActionType.markEmbyWatched),
      hasLength(1),
    );
    expect(
      plan.actions.where((a) => a.type == TraktActionType.clearEmbyProgress),
      hasLength(1),
    );
    expect(
      plan.actions.where((a) => a.type == TraktActionType.deleteTraktPlayback),
      hasLength(1),
    );
    expect(
      plan.actions.where((a) => a.type == TraktActionType.writeEmbyProgress),
      isEmpty,
    );
    expect(
      plan.actions.where((a) => a.type == TraktActionType.pauseTrakt),
      isEmpty,
    );
    expect(plan.stats.movies, 1);
  });

  test('全部未看 → 取最大进度写回落后服务器并上报 Trakt', () {
    final plan = _planner.build(
      local: [
        _movie(server: 'a', item: 'a1', position: 30000),
        _movie(server: 'b', item: 'b1', position: 60000),
      ],
      remote: [_movie(server: '', item: null, progressPercent: 40)],
    );

    final writes = plan.actions
        .where((a) => a.type == TraktActionType.writeEmbyProgress)
        .toList();
    expect(writes, hasLength(1));
    expect(writes.single.itemId, 'a1');
    expect(writes.single.positionMs, 60000);
    final pause =
        plan.actions.where((a) => a.type == TraktActionType.pauseTrakt).single;
    expect(pause.progressPercent, closeTo(60, 0.001));
  });

  test('Trakt 进度领先 → 写回 Emby，不重复上报', () {
    final plan = _planner.build(
      local: [_movie(server: 'a', item: 'a1', position: 10000)],
      remote: [_movie(server: '', item: null, progressPercent: 70)],
    );

    final write = plan.actions
        .where((a) => a.type == TraktActionType.writeEmbyProgress)
        .single;
    expect(write.positionMs, 70000);
    expect(
      plan.actions.where((a) => a.type == TraktActionType.pauseTrakt),
      isEmpty,
    );
  });

  test('单集按剧集身份跨服务器匹配，已看补齐并写入季度/集数', () {
    final plan = _planner.build(
      local: [
        _episode(server: 'a', item: 'a-e1', watched: true),
        _episode(server: 'b', item: 'b-e1'),
      ],
      remote: const [],
    );

    expect(
      plan.actions
          .where((a) => a.type == TraktActionType.markEmbyWatched)
          .map((a) => a.itemId),
      ['b-e1'],
    );
    final history = plan.actions
        .where((a) => a.type == TraktActionType.addTraktHistory)
        .single;
    expect(history.entry?.showIds.tmdb, 10);
    expect(history.entry?.season, 1);
    expect(history.entry?.episode, 2);
    expect(plan.stats.shows, 0);
    expect(plan.stats.episodes, 0);
  });

  test('未匹配 Trakt 的本地条目不计入同步统计', () {
    final plan = _planner.build(
      local: [_movie(server: 'a', item: 'a1', position: 1000)],
      remote: const [],
    );

    expect(plan.stats.movies, 0);
    expect(plan.stats.shows, 0);
    expect(plan.stats.episodes, 0);
  });

  test('接近片尾的未看进度写入 Emby 时限制在 89% 以内', () {
    final plan = _planner.build(
      local: [
        _movie(server: 'a', item: 'a1', position: 10000, runtime: 100000),
        _movie(server: 'b', item: 'b1', position: 95000, runtime: 100000),
      ],
      remote: const [],
    );

    final write = plan.actions
        .where((a) => a.type == TraktActionType.writeEmbyProgress)
        .single;
    expect(write.positionMs, 89000);
  });
}

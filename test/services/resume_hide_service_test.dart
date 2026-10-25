import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/resume_hide_service.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server(String id) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.local',
      serverName: '服务器$id',
      serverId: '$id-sid',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

MediaItem _movie(String id, String tmdb) => MediaItem(
      id: id,
      name: '电影$tmdb',
      type: 'Movie',
      providerIds: {'Tmdb': tmdb},
    );

MediaItem _episode(String id, String tmdb, int number) => MediaItem(
      id: id,
      name: '第$number集',
      type: 'Episode',
      seriesName: '剧集',
      parentIndexNumber: 1,
      indexNumber: number,
      providerIds: {'Tmdb': tmdb},
    );

void main() {
  test('同一电影在所有在线服务器联动移除', () async {
    final source = FakeEmbyService();
    final other = FakeEmbyService(
      resumeItems: [_movie('b-m1', '1')],
    );
    final different = FakeEmbyService(
      resumeItems: [_movie('c-m2', '2')],
    );
    final service = ResumeHideService(
      serviceFactory: (server) => switch (server.id) {
        'b' => other,
        'c' => different,
        _ => source,
      },
    );

    final result = await service.hideAcrossServers(
      item: _movie('a-m1', '1'),
      sourceServerId: 'a',
      servers: [_server('a'), _server('b'), _server('c')],
    );

    expect(result.sourceSucceeded, isTrue);
    expect(source.removedResumeCalls, ['a-m1']);
    expect(other.removedResumeCalls, ['b-m1']);
    expect(different.removedResumeCalls, isEmpty);
  });

  test('同剧不同集不会误移除', () async {
    final source = FakeEmbyService();
    final other = FakeEmbyService(
      resumeItems: [_episode('b-e2', '20', 2)],
    );
    final service = ResumeHideService(
      serviceFactory: (server) => server.id == 'b' ? other : source,
    );

    await service.hideAcrossServers(
      item: _episode('a-e1', '10', 1),
      sourceServerId: 'a',
      servers: [_server('a'), _server('b')],
    );

    expect(source.removedResumeCalls, ['a-e1']);
    expect(other.removedResumeCalls, isEmpty);
  });

  test('来源服务器失败时返回失败', () async {
    final source = FakeEmbyService()..removeResumeResult = false;
    final service = ResumeHideService(serviceFactory: (_) => source);

    final result = await service.hideAcrossServers(
      item: _movie('a-m1', '1'),
      sourceServerId: 'a',
      servers: [_server('a')],
    );

    expect(result.sourceSucceeded, isFalse);
  });
}

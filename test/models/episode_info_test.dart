import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/episode_info.dart';

void main() {
  group('EpisodeInfo.copyWith（播放器切版本重写 mediaSourceId）', () {
    const base = EpisodeInfo(
      id: 'ep1',
      name: '第1集',
      season: 1,
      number: 1,
      poster: 'p',
      seriesName: '剧名',
      mediaSourceId: 'srcA',
      serverId: 'srv',
    );

    test('替换 mediaSourceId，其余字段保留', () {
      final next = base.copyWith(mediaSourceId: 'srcB');
      expect(next.id, 'ep1');
      expect(next.name, '第1集');
      expect(next.season, 1);
      expect(next.number, 1);
      expect(next.poster, 'p');
      expect(next.seriesName, '剧名');
      expect(next.serverId, 'srv');
      expect(next.mediaSourceId, 'srcB');
    });

    test('不传参数时 mediaSourceId 保持原值', () {
      expect(base.copyWith().mediaSourceId, 'srcA');
    });
  });
}

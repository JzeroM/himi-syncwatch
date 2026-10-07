import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_candidate.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';

MatchCandidate _c(int id, String anime, String ep) =>
    MatchCandidate(episodeId: id, animeTitle: anime, episodeTitle: ep);

void main() {
  group('DanmakuCandidateSelector.animeYear', () {
    test('半角/全角括号年份', () {
      expect(
          DanmakuCandidateSelector.animeYear('凡人修仙传(2025)【电视剧】from 360'),
          2025);
      expect(
          DanmakuCandidateSelector.animeYear('凡人修仙传（2020）【动漫】'), 2020);
      expect(DanmakuCandidateSelector.animeYear('无年份作品'), isNull);
    });
  });

  group('DanmakuCandidateSelector.allowed（错源排除）', () {
    test('年份不符排除；无年份保留', () {
      expect(
        DanmakuCandidateSelector.allowed('凡人修仙传(2025)【电视剧】',
            year: 2020, kind: 'series'),
        isFalse,
        reason: '2025 ≠ Emby 2020 → 排除同名真人剧',
      );
      expect(
        DanmakuCandidateSelector.allowed('凡人修仙传(2020)【动漫】',
            year: 2020, kind: 'series'),
        isTrue,
      );
      expect(
        DanmakuCandidateSelector.allowed('某剧无年份', year: 2020),
        isTrue,
        reason: '无年份候选不误杀',
      );
    });

    test('电影排除电视剧类型；剧集排除电影类型', () {
      expect(
        DanmakuCandidateSelector.allowed('某片(2020)【电视剧】', kind: 'movie'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.allowed('某片(2020)【电影】', kind: 'series'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.allowed('某片(2020)【电影】', kind: 'movie'),
        isTrue,
      );
    });
  });

  group('DanmakuCandidateSelector.ordered', () {
    test('match 候选在前、搜索候选在后；集号命中优先；去重', () {
      final matched = [
        _c(1, '剧(2020)【动漫】', '第5集'),
        _c(2, '剧(2020)【动漫】', '第1集'),
      ];
      final searched = [
        _c(2, '剧(2020)【动漫】', '第1集'), // 与 match 重复
        _c(3, '剧(2020)【动漫】', '第1集'),
      ];
      final ids = DanmakuCandidateSelector.ordered(
        matched,
        searched,
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
      );
      expect(ids, [2, 1, 3], reason: '集号命中(2)排前，其余 match(1) 次之，再搜索(3)');
    });

    test('错源排除后不可用候选被丢弃', () {
      final matched = [
        _c(32709, '凡人修仙传(2025)【电视剧】from 360', '第1集'),
      ];
      final searched = [
        _c(32514, '凡人修仙传(2020)【动漫】from 360', '第1集'),
        _c(32742, '凡人修仙传：风起天南(2020)【国漫】', '第1话'),
      ];
      final ids = DanmakuCandidateSelector.ordered(
        matched,
        searched,
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
      );
      expect(ids.contains(32709), isFalse, reason: '2025 电视剧版被排除');
      expect(ids.first, 32514, reason: '2020 动漫第1集优先');
      expect(ids, contains(32742));
    });

    test('全部被排除 → 空列表（调用方提示未匹配）', () {
      final ids = DanmakuCandidateSelector.ordered(
        [_c(1, '剧(2025)【电视剧】', '第1集')],
        const [],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
      );
      expect(ids, isEmpty);
    });

    test('年份未知时不排除', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [_c(9, '剧(2025)【电视剧】', '第1集')],
        episodeNumber: 1,
        kind: null,
      );
      expect(ids, [9]);
    });
  });
}

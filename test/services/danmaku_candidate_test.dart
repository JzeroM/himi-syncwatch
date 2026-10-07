import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_candidate.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';

MatchCandidate _c(int id, String anime, String ep) =>
    MatchCandidate(episodeId: id, animeTitle: anime, episodeTitle: ep);

void main() {
  group('DanmakuCandidateSelector.animeYear / validYear', () {
    test('半角/全角括号年份', () {
      expect(
          DanmakuCandidateSelector.animeYear('凡人修仙传(2025)【电视剧】from 360'),
          2025);
      expect(
          DanmakuCandidateSelector.animeYear('凡人修仙传（2020）【动漫】'), 2020);
      expect(DanmakuCandidateSelector.animeYear('无年份作品'), isNull);
    });

    test('validYear 只接受合理年份', () {
      expect(DanmakuCandidateSelector.validYear(2020), 2020);
      expect(DanmakuCandidateSelector.validYear(null), isNull);
      expect(DanmakuCandidateSelector.validYear(0), isNull);
      expect(DanmakuCandidateSelector.validYear(99), isNull);
      expect(DanmakuCandidateSelector.validYear(3000), isNull);
    });
  });

  group('DanmakuCandidateSelector.typeAllowed（类型排除）', () {
    test('电影排除电视剧类型；剧集排除电影类型', () {
      expect(
        DanmakuCandidateSelector.typeAllowed('某片(2020)【电视剧】', kind: 'movie'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某片(2020)【电影】', kind: 'series'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某片(2020)【电影】', kind: 'movie'),
        isTrue,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某剧(2020)【动漫】', kind: 'series'),
        isTrue,
      );
    });
  });

  group('DanmakuCandidateSelector.ordered', () {
    test('回归：Emby 年份不准也不误杀唯一正确候选（凡人修仙传 E194）', () {
      // Emby 年份 2025（错误/连载年份），正确源标注 2020 → 不再排除
      final ids = DanmakuCandidateSelector.ordered(
        [_c(32707, '凡人修仙传(2020)【动漫】from 360', '【bilibili1】 第194集')],
        const [],
        episodeNumber: 194,
        year: 2025,
        kind: 'series',
      );
      expect(ids, [32707]);
    });

    test('年份降权：同名 2020/2025 集号命中时，同年 2020 排前', () {
      final ids = DanmakuCandidateSelector.ordered(
        [
          _c(32709, '凡人修仙传(2025)【电视剧】', '第1集'),
        ],
        [
          _c(32514, '凡人修仙传(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
      );
      // 同为集号命中，同年(2020)优先 → 32514 排前，2025 保留兜底
      expect(ids, [32514, 32709]);
    });

    test('无年份信息（year=null）不做年份降权，保持原顺序', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [
          _c(1, '剧(2025)【电视剧】', '第1集'),
          _c(2, '剧(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: null,
        kind: 'series',
      );
      expect(ids, [1, 2]);
    });

    test('异年候选不丢弃，仅排到同年之后', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [
          _c(1, '剧(2025)【电视剧】', '第1集'),
          _c(2, '剧(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
      );
      expect(ids, [2, 1], reason: '同年(2)在前，异年(1)兜底保留');
    });

    test('集号命中优先于分组；同年同命中时 match 在 search 前；去重', () {
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
      expect(ids, [2, 3, 1],
          reason: '同命中：match(2) 在 search(3) 前；未命中的 match(1) 最后');
    });

    test('类型不符被丢弃', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [
          _c(1, '某片(2020)【电视剧】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'movie',
      );
      expect(ids, isEmpty);
    });
  });
}

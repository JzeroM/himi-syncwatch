import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_candidate.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';

MatchCandidate _c(int id, String anime, String ep) =>
    MatchCandidate(episodeId: id, animeTitle: anime, episodeTitle: ep);

void main() {
  group('DanmakuCandidateSelector.year', () {
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

  group('DanmakuCandidateSelector.typeAllowed（类型错源排除）', () {
    test('动画资源排除真人剧类，保留动画/电影类', () {
      for (final t in const ['电视剧', '国产剧', '韩剧', '美剧', '短剧']) {
        expect(
          DanmakuCandidateSelector.typeAllowed('某作品(2020)【$t】',
              isAnimation: true),
          isFalse,
          reason: '动画资源不匹配 $t',
        );
      }
      for (final t in const ['动漫', '国漫', '电影', '动画电影', '剧场版']) {
        expect(
          DanmakuCandidateSelector.typeAllowed('某作品(2020)【$t】',
              isAnimation: true),
          isTrue,
          reason: '动画资源允许 $t',
        );
      }
    });

    test('非动画电影排除真人剧类', () {
      expect(
        DanmakuCandidateSelector.typeAllowed('某片(2020)【电视剧】', kind: 'movie'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某片(2020)【华语电影】', kind: 'movie'),
        isTrue,
      );
    });

    test('非动画剧集排除动画类与电影类', () {
      expect(
        DanmakuCandidateSelector.typeAllowed('某剧(2020)【动漫】', kind: 'series'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某剧(2020)【电影】', kind: 'series'),
        isFalse,
      );
      expect(
        DanmakuCandidateSelector.typeAllowed('某剧(2020)【电视剧】', kind: 'series'),
        isTrue,
      );
    });

    test('无动画信号且无 kind → 不过滤', () {
      expect(
        DanmakuCandidateSelector.typeAllowed('任意(2020)【电视剧】'),
        isTrue,
      );
    });
  });

  group('DanmakuCandidateSelector.ordered', () {
    test('回归：match 挑错集(第103话)，搜索的集号命中(第194话)优先', () {
      final ids = DanmakuCandidateSelector.ordered(
        [_c(32844, '凡人修仙传：风起天南(2020)【国漫】', '【bilibili1】 第103话 星海飞驰27')],
        [_c(33031, '凡人修仙传：风起天南(2020)【国漫】', '【bilibili1】 第194话 慕兰之战18')],
        episodeNumber: 194,
        year: 2026, // Emby 年份=更新年，与源 2020 不一致
        kind: 'series',
        isAnimation: true,
      );
      expect(ids, [33031, 32844], reason: '集号命中优先，异年不丢');
    });

    test('动画资源排除 2025 电视剧版，保留 2020 动漫', () {
      final ids = DanmakuCandidateSelector.ordered(
        [_c(32709, '凡人修仙传(2025)【电视剧】', '第1集')],
        [
          _c(32514, '凡人修仙传(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
        isAnimation: true,
      );
      expect(ids, [32514], reason: '【电视剧】被类型排除');
    });

    test('全局集号命中优先于来源分组（match 非命中 vs search 命中）', () {
      final ids = DanmakuCandidateSelector.ordered(
        [
          _c(1, '剧(2020)【动漫】', '第5集'),
          _c(2, '剧(2020)【动漫】', '第1集'),
        ],
        [
          _c(2, '剧(2020)【动漫】', '第1集'), // 与 match 重复
          _c(3, '剧(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
        isAnimation: true,
      );
      expect(ids, [2, 3, 1],
          reason: '同命中：match(2) 在 search(3) 前；未命中的 match(1) 最后');
    });

    test('年份降权：异年候选保留，仅排到同年之后', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [
          _c(1, '剧(2025)【动漫】', '第1集'),
          _c(2, '剧(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: 2020,
        kind: 'series',
        isAnimation: true,
      );
      expect(ids, [2, 1], reason: '同年(2)在前，异年(1)兜底保留');
    });

    test('无年份信息不降权，保持原顺序', () {
      final ids = DanmakuCandidateSelector.ordered(
        const [],
        [
          _c(1, '剧(2025)【动漫】', '第1集'),
          _c(2, '剧(2020)【动漫】', '第1集'),
        ],
        episodeNumber: 1,
        year: null,
        kind: 'series',
        isAnimation: true,
      );
      expect(ids, [1, 2]);
    });
  });
}

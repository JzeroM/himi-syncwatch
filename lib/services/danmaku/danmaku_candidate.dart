import 'danmaku_matcher.dart';
import 'dandanplay_client.dart';

/// 弹幕候选筛选与排序（纯逻辑，无 IO，便于单测）。
///
/// 目标：
/// - **错源排除**：已知 Emby 年份/类型时，剔除明显不符的同名作品
///   （如「凡人修仙传(2025)【电视剧】」vs 动漫资源）；
/// - **有序候选**：集号匹配优先；`match` 候选在前、搜索候选在后；去重。
class DanmakuCandidateSelector {
  const DanmakuCandidateSelector._();

  /// 从 danmu 作品名解析年份：`凡人修仙传(2020)【…】` → 2020；无 → null。
  static int? animeYear(String animeTitle) {
    final m = RegExp(r'[\(（](\d{4})[\)）]').firstMatch(animeTitle);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 候选是否与当前 Emby 资源相容：
  /// - 已知 Emby `year` → 排除「有明确年份且不符」的候选（无年份候选保留）；
  /// - `kind == 'movie'` → 排除「电视剧」类型；
  /// - 非电影 `kind` → 排除「电影」类型。
  static bool allowed(String animeTitle, {int? year, String? kind}) {
    final animeYearValue = animeYear(animeTitle);
    if (year != null && animeYearValue != null && animeYearValue != year) {
      return false;
    }
    if (kind == 'movie' && animeTitle.contains('电视剧')) return false;
    if (kind != null && kind != 'movie' && animeTitle.contains('电影')) {
      return false;
    }
    return true;
  }

  /// 组装有序候选 episodeId：
  /// 1. [matched] 组内：集号命中排前、其余排后；
  /// 2. 再排 [searched] 组（同样集号命中排前）；
  /// 3. 被 [allowed] 排除的候选丢弃；episodeId 去重（先出现者优先）。
  static List<int> ordered(
    List<MatchCandidate> matched,
    List<MatchCandidate> searched, {
    required int episodeNumber,
    int? year,
    String? kind,
  }) {
    final seen = <int>{};
    final out = <int>[];
    void addGroup(List<MatchCandidate> group) {
      final hits = <MatchCandidate>[];
      final rest = <MatchCandidate>[];
      for (final c in group) {
        if (!allowed(c.animeTitle, year: year, kind: kind)) continue;
        if (episodeNumber > 0 &&
            DanmakuMatcher.parseEpisodeNumber(c.episodeTitle) ==
                episodeNumber) {
          hits.add(c);
        } else {
          rest.add(c);
        }
      }
      for (final c in [...hits, ...rest]) {
        if (seen.add(c.episodeId)) out.add(c.episodeId);
      }
    }

    addGroup(matched);
    addGroup(searched);
    return out;
  }
}

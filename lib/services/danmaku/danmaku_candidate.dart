import 'danmaku_matcher.dart';
import 'dandanplay_client.dart';

/// 弹幕候选筛选与排序（纯逻辑，无 IO，便于单测）。
///
/// 目标：
/// - **错源排除**：已知 Emby 类型时剔除明显不符的候选（电影 ↔ 电视剧）；
/// - **年份降权（不排除）**：与 Emby 年份一致的候选排前，不一致的保留在
///   末尾兜底 —— Emby 对连载动画的 `ProductionYear` 常与弹幕源标注年份不同
///   （或为 0/异常），严格排除会误杀正确源（如「凡人修仙传」E194）；
/// - **有序候选**：集号匹配优先；`match` 候选在前、搜索候选在后；去重。
class DanmakuCandidateSelector {
  const DanmakuCandidateSelector._();

  /// 从 danmu 作品名解析年份：`凡人修仙传(2020)【…】` → 2020；无 → null。
  static int? animeYear(String animeTitle) {
    final m = RegExp(r'[\(（](\d{4})[\)）]').firstMatch(animeTitle);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 年份是否可信（在合理区间内）；0/空/异常返回 null（视为无年份信息）。
  static int? validYear(int? year) =>
      (year != null && year >= 1900 && year <= 2100) ? year : null;

  /// 类型是否相容：`kind == 'movie'` 排除「电视剧」；其它 `kind` 排除「电影」。
  /// 年份不在此处排除（改由 [ordered] 降权处理）。
  static bool typeAllowed(String animeTitle, {String? kind}) {
    if (kind == 'movie' && animeTitle.contains('电视剧')) return false;
    if (kind != null && kind != 'movie' && animeTitle.contains('电影')) {
      return false;
    }
    return true;
  }

  /// 组装有序候选 episodeId（每项只出现一次）：
  /// 1. 集号命中优先；
  /// 2. 同年优先（年份不符的排后兜底，不丢弃）；
  /// 3. 同年同命中时 `matched` 组排在 `searched` 组之前；
  /// 4. 类型不符（电影↔电视剧）的直接丢弃。
  static List<int> ordered(
    List<MatchCandidate> matched,
    List<MatchCandidate> searched, {
    required int episodeNumber,
    int? year,
    String? kind,
  }) {
    final embyYear = validYear(year);
    // 桶序（低→高优先级）：
    //   命中+同年(match) / 命中+同年(search) / 命中+异年(match) / 命中+异年(search)
    //   未命中+同年(match) / 未命中+同年(search) / 未命中+异年(match) / 未命中+异年(search)
    final buckets = List.generate(8, (_) => <MatchCandidate>[]);

    void addGroup(List<MatchCandidate> group, int groupIndex) {
      for (final c in group) {
        if (!typeAllowed(c.animeTitle, kind: kind)) continue;
        final hit = episodeNumber > 0 &&
            DanmakuMatcher.parseEpisodeNumber(c.episodeTitle) == episodeNumber;
        final animeYearValue = animeYear(c.animeTitle);
        // 无年份信息视为中性（与同年同桶）；仅「有明确年份且不符」算异年
        final yearBad = embyYear != null &&
            animeYearValue != null &&
            animeYearValue != embyYear;
        final index = (hit ? 0 : 4) + (yearBad ? 2 : 0) + groupIndex;
        buckets[index].add(c);
      }
    }

    addGroup(matched, 0);
    addGroup(searched, 1);

    final seen = <int>{};
    final out = <int>[];
    for (final bucket in buckets) {
      for (final c in bucket) {
        if (seen.add(c.episodeId)) out.add(c.episodeId);
      }
    }
    return out;
  }
}

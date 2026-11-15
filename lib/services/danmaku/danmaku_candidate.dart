import 'danmaku_matcher.dart';
import 'dandanplay_client.dart';

/// 弹幕候选筛选与排序（纯逻辑，无 IO，便于单测）。
///
/// 目标：
/// - **类型错源排除**：依据 Emby 的「动画」类型（[isAnimation]）排除明显不符
///   的同名作品（动画资源 ↔ 真人剧；无该类型时回退内容类型 [kind]）；
/// - **年份降权（不排除）**：与 Emby 年份一致的候选排前，不一致的保留末尾兜底
///   —— Emby 对连载动画的年份常为开播年/最新更新年，与弹幕源标注不一致
///   （如「凡人修仙传」2020 开播、194 集 2026 更新）；
/// - **全局集号命中优先**：只要某候选集号与目标一致，就排在所有非命中候选前，
///   不受 `match`/搜索来源分组限制 —— 修复 `match` 挑错集（如 E194 → 第103话）。
class DanmakuCandidateSelector {
  const DanmakuCandidateSelector._();

  /// 真人剧类 typeDescription。
  static const List<String> liveActionTypes = [
    '电视剧',
    '国产剧',
    '韩剧',
    '美剧',
    '短剧',
  ];

  /// 动画类 typeDescription。
  static const List<String> animationTypes = [
    '动漫',
    '动画',
    '国漫',
    '日番',
    '动画电影',
    '剧场版',
  ];

  /// 从 danmu 作品名解析年份：`凡人修仙传(2020)【…】` → 2020；无 → null。
  static int? animeYear(String animeTitle) {
    final m = RegExp(r'[\(（](\d{4})[\)）]').firstMatch(animeTitle);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 年份是否可信（在合理区间内）；0/空/异常返回 null（视为无年份信息）。
  static int? validYear(int? year) =>
      (year != null && year >= 1900 && year <= 2100) ? year : null;

  static bool _hasAny(String animeTitle, List<String> types) =>
      types.any(animeTitle.contains);

  /// 类型是否相容（年份不在此排除，改由 [ordered] 降权）：
  /// - 动画资源（isAnimation）→ 排除真人剧类；
  /// - 电影（kind=movie）→ 排除真人剧类；
  /// - 剧集且非动画 → 排除动画类与「电影」；
  /// - 无动画信号且无 kind → 不过滤。
  static bool typeAllowed(String animeTitle, {String? kind, bool isAnimation = false}) {
    if (isAnimation) {
      return !_hasAny(animeTitle, liveActionTypes);
    }
    if (kind == 'movie') {
      return !_hasAny(animeTitle, liveActionTypes);
    }
    if (kind != null) {
      // 剧集且未标注动画：排除动画类与电影类
      return !_hasAny(animeTitle, animationTypes) &&
          !animeTitle.contains('电影');
    }
    return true;
  }

  /// 标题相似度（694 M5：token Jaccard 为主、编辑距离为辅；纯函数）。
  ///
  /// 用作同桶内 tiebreak——不改变桶级语义（集号命中/年份/来源），
  /// 只细分「同优先级」候选的先后。
  static double titleSimilarity(String a, String b) {
    final la = a.trim().toLowerCase();
    final lb = b.trim().toLowerCase();
    if (la.isEmpty || lb.isEmpty) return 0;
    final ta = _tokens(la);
    final tb = _tokens(lb);
    final inter = ta.intersection(tb).length;
    final union = ta.length + tb.length - inter;
    final jaccard = union == 0 ? 0.0 : inter / union;
    final lev = _levenshtein(la, lb);
    final maxLen = la.length > lb.length ? la.length : lb.length;
    final levScore = maxLen == 0 ? 0.0 : 1 - lev / maxLen;
    return jaccard * 0.7 + levScore * 0.3;
  }

  static Set<String> _tokens(String s) =>
      s.split(RegExp(r'[^\p{L}\p{Nd}]+', unicode: true))
          .where((t) => t.isNotEmpty)
          .toSet();

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [
          cur[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[b.length];
  }

  /// 组装有序候选 episodeId（每项只出现一次）：
  /// 1. 集号命中优先（跨来源全局优先）；
  /// 2. 同年优先（异年保留末尾兜底）；
  /// 3. 同级内 `matched` 组排在 `searched` 组之前；
  /// 4. 类型不符的直接丢弃。
  /// 5.（694 M5）同桶内按 [title] 相似度细分；无标题信息的候选排桶尾。
  ///    [title] 为空时保持原序（不劣化现状）。
  static List<int> ordered(
    List<MatchCandidate> matched,
    List<MatchCandidate> searched, {
    required int episodeNumber,
    int? year,
    String? kind,
    bool isAnimation = false,
    String title = '',
  }) {
    final embyYear = validYear(year);
    // 桶序（低→高优先级）：
    //   命中+同年(match) / 命中+同年(search) / 命中+异年(match) / 命中+异年(search)
    //   非命中+同年(match) / 非命中+同年(search) / 非命中+异年(match) / 非命中+异年(search)
    final buckets = List.generate(8, (_) => <MatchCandidate>[]);

    void addGroup(List<MatchCandidate> group, int groupIndex) {
      for (final c in group) {
        if (!typeAllowed(c.animeTitle, kind: kind, isAnimation: isAnimation)) {
          continue;
        }
        final hit = episodeNumber > 0 &&
            DanmakuMatcher.parseEpisodeNumber(c.episodeTitle) == episodeNumber;
        final animeYearValue = animeYear(c.animeTitle);
        // 无年份信息视为中性（与同年同桶）；仅「有明确年份且不符」算异年
        final yearBad = embyYear != null &&
            animeYearValue != null &&
            animeYearValue != embyYear;
        buckets[(hit ? 0 : 4) + (yearBad ? 2 : 0) + groupIndex].add(c);
      }
    }

    addGroup(matched, 0);
    addGroup(searched, 1);

    // 694 M5：同桶内按标题相似度稳定细分（title 为空 = 保持原序）。
    final ref = title.trim();
    if (ref.isNotEmpty) {
      for (final bucket in buckets) {
        final indexed = [
          for (var i = 0; i < bucket.length; i++) (i, bucket[i]),
        ];
        double scoreOf(MatchCandidate c) => c.animeTitle.isEmpty
            ? -1 // 无标题信息排桶尾
            : titleSimilarity(ref, c.animeTitle);
        indexed.sort((x, y) {
          final cmp = scoreOf(y.$2).compareTo(scoreOf(x.$2));
          return cmp != 0 ? cmp : x.$1.compareTo(y.$1); // 稳定
        });
        bucket
          ..clear()
          ..addAll(indexed.map((e) => e.$2));
      }
    }

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

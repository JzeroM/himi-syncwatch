// 版权声明（698 ②）：本文件的标题归一化、bigram 相似度、JSON-LD 评分抽取
// 移植自 **film-bridge**（https://github.com/niall133/film-bridge，MIT License，
// Copyright (c) 2025 niall133），由 JavaScript 改写为 Dart。移植时保留算法语义，
// 适配 Flutter 侧无浏览器 DOM 的 HTTP HTML 解析。署名与许可见
// third_party/film-bridge/NOTICE.md。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 网页评分解析工具（film-bridge 移植，698 ②）：
///
/// 豆瓣 / Letterboxd 详情页在 HTML 里内嵌 `application/ld+json` 结构化数据
/// （`schema.org/aggregateRating` 公开格式），HTTP GET 页面即可抽取评分——
/// 不需要浏览器 DOM。三级降级：JSON-LD → meta 标签 → 元素文本。
class BridgeParsers {
  /// JSON-LD 块：`<script type="application/ld+json">…</script>`（可能多个）。
  static final _jsonLdBlock = RegExp(
    r'<script[^>]*type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  );

  /// 从 HTML 抽取 `aggregateRating.ratingValue`（0 制随站点）。
  ///
  /// JSON-LD 可能是单对象或对象数组；命中任一 `aggregateRating` 即返回。
  /// 解析不出返回 null（脏 HTML / 站点改版静默降级）。
  static double? extractJsonLdRating(String html) {
    for (final m in _jsonLdBlock.allMatches(html)) {
      final raw = m.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        final json = jsonDecode(raw);
        final v = _ratingFromJsonLd(json);
        if (v != null) return v;
      } catch (_) {
        // 单块脏数据不影响其他块。
      }
    }
    return null;
  }

  static double? _ratingFromJsonLd(Object? json) {
    if (json is List) {
      for (final e in json) {
        final v = _ratingFromJsonLd(e);
        if (v != null) return v;
      }
      return null;
    }
    if (json is! Map) return null;
    final agg = json['aggregateRating'];
    if (agg is Map) {
      final v = double.tryParse('${agg['ratingValue'] ?? ''}');
      if (v != null && v > 0) return v;
    }
    return null;
  }

  /// meta 降级：`<meta property="v:average" content="8.9">`（豆瓣）或
  /// `<meta name="twitter:data2" content="4.2 average">`（Letterboxd）。
  static double? extractMetaRating(String html) {
    final vAverage = RegExp(
      r'property=["\x27]v:average["\x27][^>]*content=["\x27]([\d.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    final v1 = double.tryParse(vAverage?.group(1) ?? '');
    if (v1 != null && v1 > 0) return v1;

    final twitter = RegExp(
      r'name=["\x27]twitter:data2["\x27][^>]*content=["\x27]([\d.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    final v2 = double.tryParse(twitter?.group(1) ?? '');
    if (v2 != null && v2 > 0) return v2;
    return null;
  }

  /// 综合抽取评分：JSON-LD 优先，meta 降级。
  static double? extractRating(String html) =>
      extractJsonLdRating(html) ?? extractMetaRating(html);

  /// 豆瓣 subject 页的 IMDb id（`IMDb: tt0133093` 文本形态）→ 反补 tt id，
  /// 缺 `ProviderIds.Imdb` 的条目借此激活 OMDb 三枚（698 ②）。
  /// 先剥 HTML 标签再匹配（film-bridge `stripTags` 语义：id 前常夹标签）。
  static String? extractImdbId(String html) {
    final text = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final m = RegExp(
      r'IMDb\s*[:：]\s*(tt\d{5,12})',
      caseSensitive: false,
    ).firstMatch(text);
    return m?.group(1)?.toLowerCase();
  }

  // ── 豆瓣反爬挑战（698 N5-C）──────────────────────────────────────
  //
  // 豆瓣对非常规客户端返回「点我继续浏览」挑战页（假 200）：SHA-512
  // 工作量证明——`sha512(cha + nonce)` 十六进制前 4 位为 0（浏览器 JS
  // 挖矿平均 6.5 万次），挖到 nonce 后 POST /c 换通行 cookie。

  /// 是否为反爬挑战页（含挑战表单特征）。
  static bool isDoubanChallenge(String html) =>
      html.contains('id="tok"') && html.contains('id="cha"');

  /// 解析挑战表单（tok/cha/red/action）；特征不全返回 null。
  /// `action` 为表单原样 action（相对路径按挑战宿主解析——挑战页由
  /// `sec.douban.com` 302 后下发，698 N7-E 真机实录）。
  static Map<String, String>? parseDoubanChallenge(String html) {
    String? pick(String id) => RegExp(
          'id="$id"[^>]*value="([^"]*)"',
        ).firstMatch(html)?.group(1);
    final tok = pick('tok');
    final cha = pick('cha');
    final red = pick('red');
    if (tok == null || cha == null || red == null) return null;
    final action = RegExp(r'<form[^>]*action="([^"]*)"')
        .firstMatch(html)
        ?.group(1);
    return {'tok': tok, 'cha': cha, 'red': red, if (action != null) 'action': action};
  }

  /// 挖掘挑战 nonce（698 N5-C）：`sha512(cha + nonce)` 十六进制前
  /// [difficulty] 位为 0（挑战页 JS 同款算法，nonce 从 1 递增）。
  /// 挖不出（超 [maxIterations]）返回 null（保守放弃，不上徽章）。
  ///
  /// 难度 4 平均约 6.5 万次哈希，纯 CPU 毫秒~百毫秒级；测试可用小难度快跑。
  static String? mineDoubanNonce(
    String cha, {
    int difficulty = 4,
    int maxIterations = 2000000,
  }) {
    final target = '0' * difficulty;
    for (var nonce = 1; nonce <= maxIterations; nonce++) {
      final hex = sha512.convert(utf8.encode(cha + '$nonce')).toString();
      if (hex.startsWith(target)) return '$nonce';
    }
    return null;
  }

  /// 从豆瓣搜索结果页抽 subject 候选（698 N7-E 三级）：
  /// ① HTML 锚点（`/subject/(\d+)/` + 铉文本）；
  /// ② `window.__DATA__` 内嵌 JSON（递归收集 `{id, title}`，防 JS 渲染页）。
  /// 返回 `{'id': '3541415', 'title': '盗梦空间 Inception'}…`（顺序保留、去重）。
  static List<Map<String, String>> extractDoubanSubjects(String html) {
    final out = <Map<String, String>>[];
    final seen = <String>{};
    // ① 锚点（搜索页结构：`<a href="…/subject/3541415/" …>盗梦空间</a>`）。
    final linkRe = RegExp(
      r'href="[^"]*movie\.douban\.com/subject/(\d+)/[^"]*"[^>]*>([\s\S]{1,120}?)</a>',
      caseSensitive: false,
    );
    for (final m in linkRe.allMatches(html)) {
      final id = m.group(1)!;
      if (!seen.add(id)) continue;
      final title = normalizeWhitespace(
        (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
      );
      out.add({'id': id, 'title': title});
      if (out.length >= 12) break;
    }
    // ② window.__DATA__ JSON（新搜索页把结果放内嵌 JSON，锚点可能缺席）。
    final blob = _extractJsonObject(html, 'window.__DATA__');
    if (blob != null) {
      try {
        _collectSubjects(jsonDecode(blob), seen, out);
      } catch (_) {
        // 脏 JSON：锚点路径已尽力。
      }
    }
    return out;
  }

  /// 从 `marker = {...}` 起按花括号配平截出完整 JSON 对象（字符串感知）。
  static String? _extractJsonObject(String html, String marker) {
    final start = html.indexOf(marker);
    if (start < 0) return null;
    final eq = html.indexOf('=', start + marker.length);
    if (eq < 0) return null;
    var i = html.indexOf('{', eq);
    if (i < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (; i < html.length; i++) {
      final c = html[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') inString = !inString;
      if (inString) continue;
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return html.substring(eq + 1, i + 1);
      }
    }
    return null;
  }

  /// 递归收集 `{id, title}` 形态的 subject 候选（schema 无关）。
  static void _collectSubjects(
    Object? node,
    Set<String> seen,
    List<Map<String, String>> out,
  ) {
    if (out.length >= 12) return;
    if (node is List) {
      for (final e in node) {
        _collectSubjects(e, seen, out);
      }
      return;
    }
    if (node is! Map) return;
    final id = node['id'];
    final title = node['title'];
    if (id != null && title is String && title.isNotEmpty) {
      final idStr = '$id';
      if (RegExp(r'^\d{5,12}$').hasMatch(idStr) && seen.add(idStr)) {
        out.add({'id': idStr, 'title': normalizeWhitespace(title)});
      }
    }
    for (final v in node.values) {
      _collectSubjects(v, seen, out);
    }
  }

  // ── 标题匹配（film-bridge shared.js 移植）──────────────────────────

  /// 空白归一（含全角空格/NBSP）。
  static String normalizeWhitespace(String value) {
    return value
        .replaceAll(RegExp(r'[\u00a0\u2000-\u200b\u202f\u205f\u3000]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 抽年份（18/19/20/21 开头四位）。
  static int? parseYear(String? value) {
    final m = RegExp(r'(?:^|\D)((?:18|19|20|21)\d{2})(?:\D|$)').firstMatch(
      value ?? '',
    );
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 标题归一：去站点后缀/年份 → NFKD → 去音标 → 小写 → 仅留字母数字。
  static String normalizeTitle(String value) {
    var v = normalizeWhitespace(value)
        .replaceAll(RegExp(r'\s*[·•]\s*(?:Letterboxd|豆瓣电影)\s*$'), '')
        .replaceAll(RegExp(r'\s*[-–—]\s*(?:Letterboxd|豆瓣电影|IMDb|TMDB|Metacritic)\s*$'), '')
        .replaceAll(RegExp(r'\s*[（(](?:18|19|20|21)\d{2}[）)]\s*$'), '')
        .trim();
    v = _removeDiacritics(v).toLowerCase();
    v = v.replaceAll(RegExp(r'[^\p{Letter}\p{Number}]+', unicode: true), '');
    return v;
  }

  /// NFKD 分解后去除组合音标（film-bridge 的 `normalize("NFKD") + \p{Mark}`）。
  static String _removeDiacritics(String value) {
    // Dart 无内置 NFKD；常见欧洲音标手工映射（豆瓣/Littleboxd 标题够用）。
    const map = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n', 'ç': 'c', 'ß': 'ss',
    };
    var out = value;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  /// bigram Dice 相似度（0–1）：完全相同 1，包含关系按长度比 ×0.92，
  /// 其余按二元组重合度。film-bridge `titleSimilarity` 逐语义移植。
  static double titleSimilarity(String left, String right) {
    final a = normalizeTitle(left);
    final b = normalizeTitle(right);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) {
      final shorter = a.length < b.length ? a.length : b.length;
      final longer = a.length < b.length ? b.length : a.length;
      return shorter / longer * 0.92;
    }
    final ag = _bigrams(a);
    final bg = _bigrams(b);
    var overlap = 0;
    for (final g in ag) {
      if (bg.contains(g)) overlap++;
    }
    return 2 * overlap / (ag.length + bg.length);
  }

  static Set<String> _bigrams(String value) {
    if (value.length < 2) return {value};
    final out = <String>{};
    for (var i = 0; i < value.length - 1; i++) {
      out.add(value.substring(i, i + 2));
    }
    return out;
  }
}

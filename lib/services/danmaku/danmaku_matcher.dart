/// 弹幕文件识别输入构造（纯 Dart，无 IO，便于单测）。
///
/// 识别优先级：Emby `Path` 真实文件名 → 剧集构造（`剧名.S01E02`，
/// danmu_api 与弹弹play 均按 title+season+episode 解析）→ 单集名称。
class DanmakuMatcher {
  const DanmakuMatcher._();

  /// Windows/Unix 路径 basename（同时按 `\` 与 `/` 切分）。
  static String basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /// 去掉最后一个扩展名（`file.mkv` → `file`；无扩展名原样返回）。
  /// 中段多点（`S01E01.2160p.WEB-DL`）只剥最后一段。
  static String stripExtension(String fileName) {
    final idx = fileName.lastIndexOf('.');
    if (idx <= 0) return fileName;
    return fileName.substring(0, idx);
  }

  /// Emby `Path` → 匹配用文件名；null/空返回 null。
  static String? fromPath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final name = stripExtension(basename(path.trim()));
    return name.isEmpty ? null : name;
  }

  /// 剧集 → `剧名.SxxExx`（零填充 2 位）；非剧集（season/number ≤ 0）
  /// 或缺剧名 → [name]。
  ///
  /// 694 M1：season/number 缺失时从 [name] 兜底解析（`SxxExx` / `1x02`），
  /// 让「文件名带集号但 Emby 元数据缺季/集」的场景也能构造标准匹配名。
  static String fromEpisode({
    required String name,
    String seriesName = '',
    int season = 0,
    int number = 0,
  }) {
    final series = seriesName.trim();
    var s = season;
    var n = number;
    if (s <= 0 || n <= 0) {
      final parsed = parseSeasonEpisode(name);
      if (parsed != null) {
        s = parsed.season;
        n = parsed.episode;
      }
    }
    if (s > 0 && n > 0 && series.isNotEmpty) {
      return '$series.'
          'S${s.toString().padLeft(2, '0')}'
          'E${n.toString().padLeft(2, '0')}';
    }
    return name.trim();
  }

  /// 汇总解析：Path 优先，其次剧集构造，最后单集名称；
  /// 全部为空返回 null（调用方提示未匹配）。
  static String? resolve({
    String? path,
    String name = '',
    String seriesName = '',
    int season = 0,
    int number = 0,
  }) {
    final fromEmbyPath = fromPath(path);
    if (fromEmbyPath != null) return fromEmbyPath;
    final constructed = fromEpisode(
      name: name,
      seriesName: seriesName,
      season: season,
      number: number,
    );
    return constructed.isEmpty ? null : constructed;
  }

  /// 清洗剧名用于搜索兜底：去扩展名、`SxxExx`、`(年份)`、常见发布
  /// 标签，`.`/`_` 归一为空格并压缩空白。仅用于「关键词搜索」，不改
  /// 变本地展示名。
  ///
  /// 694 M1：补剥集号残段（`1x02` / `Episode N` / ` - 01 - xxx` /
  /// `[01v2]` / `第N话`）与 `(TV)`/`(OVA)` 类标签——关键词只留剧名。
  static String cleanTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(
      RegExp(r'\.(mkv|mp4|avi|mov|ts|m2ts|webm|flv)$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[\[\(]\s*(19|20)\d{2}\s*[\]\)]'), ' ');
    // 发布命名中的 `.2023.` 年份（点分隔），不动片名里空格分隔的数字
    s = s.replaceAll(RegExp(r'(?<=[._])(19|20)\d{2}(?=[._])'), ' ');
    s = s.replaceAll(
      RegExp(
        r'\b(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|web-?dl|webrip|'
        r'hdtv|remux|hevc|h\.?265|h\.?264|avc|x265|x264|aac|dts|truehd|'
        r'atmos|ddp?[0-9](\.[0-9])?)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[._]+'), ' ');
    // ── 694 M1：集号残段（SxxExx 已在上方剥除）──
    // 1x02
    s = s.replaceAll(RegExp(r'(?<!\d)(\d{1,2})[xX](\d{1,4})(?!\d)'), ' ');
    // 「 - 01 - xxx」/「 - 01」（AniList 式命名，整段后缀丢弃）
    s = s.replaceAll(RegExp(r'\s+-\s+(?!19\d\d|20\d\d)\d{1,4}\b.*$'), ' ');
    // 「[01]」/「[01v2]」（字幕组括号集数；年份括号已在上方剥除）
    s = s.replaceAll(
      RegExp(r'\[\s*(?!19\d\d|20\d\d)\d{1,4}(?:v\d)?\s*\]'),
      ' ',
    );
    // EP/Episode/E + 数字
    s = s.replaceAll(
      RegExp(r'\b(?:EP|Episode|E)\s*\d{1,4}\b', caseSensitive: false),
      ' ',
    );
    // 「第N话/話/集/回/期」
    s = s.replaceAll(RegExp(r'第\s*\d+\s*[话話集回期]'), ' ');
    // 「(TV)」「[OVA]」类标签
    s = s.replaceAll(
      RegExp(r'[\[\(]\s*(?:tv|ova|oad|special|anime)\s*[\]\)]',
          caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  /// 从文本解析（季, 集）：`SxxExx`（S01E02/s01e02）与 `1x02` 两种显式
  /// 形态；解析不到返回 null（694 M1）。
  ///
  /// 带词边界防误判：`Files01e12` 不会命中 `s01e12`。
  static ({int season, int episode})? parseSeasonEpisode(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final se = RegExp(r'(?<![A-Za-z0-9])[Ss](\d{1,2})\s*[Ee](\d{1,4})(?!\d)')
        .firstMatch(t);
    if (se != null) {
      return (
        season: int.parse(se.group(1)!),
        episode: int.parse(se.group(2)!),
      );
    }
    final x = RegExp(r'(?<!\d)(\d{1,2})[xX](\d{1,4})(?!\d)').firstMatch(t);
    if (x != null) {
      return (
        season: int.parse(x.group(1)!),
        episode: int.parse(x.group(2)!),
      );
    }
    return null;
  }

  /// 从集标题提取集号（694 M1：全变体正则族，优先级从强到弱）：
  /// 1. `SxxExx` / `1x02`（季+集显式标注）
  /// 2. 「第N话/話/集/回/期」「EP/Episode/E + 数字」
  /// 3. 「 - NN - 」/「 - NN」（AniList 式命名，排除年份）
  /// 4. 「[NN]」/「[NNv2]」（字幕组括号集数，排除年份）
  /// 5. 开头裸数字（`01 – 标题`，排除年份）
  /// 6. 中缀裸数字（排除年份 19xx/20xx 与分辨率 480/576/720/1080/2160）
  /// 提取不到返回 null。
  static int? parseEpisodeNumber(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final se = parseSeasonEpisode(t);
    if (se != null) return se.episode;
    final cn = RegExp(r'第\s*(\d+)\s*[话話集回期]').firstMatch(t);
    if (cn != null) return int.tryParse(cn.group(1)!);
    final ep = RegExp(r'\b(?:EP|Episode|E)\s*(\d{1,4})\b', caseSensitive: false)
        .firstMatch(t);
    if (ep != null) return int.tryParse(ep.group(1)!);
    final dash = RegExp(r'\s+-\s+(?!19\d\d|20\d\d)(\d{1,4})\b').firstMatch(t);
    if (dash != null) return int.tryParse(dash.group(1)!);
    final bracket =
        RegExp(r'\[\s*(?!19\d\d|20\d\d)(\d{1,4})(?:v\d)?\s*\]').firstMatch(t);
    if (bracket != null) return int.tryParse(bracket.group(1)!);
    final bare = RegExp(r'^\s*(?!19\d\d|20\d\d)(\d{1,4})\b').firstMatch(t);
    if (bare != null) return int.tryParse(bare.group(1)!);
    // 中缀裸数字：跳过年份/分辨率，取第一个可信值
    for (final m in RegExp(r'(?<!\d)(\d{1,4})(?!\d)').allMatches(t)) {
      final raw = m.group(1)!;
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(raw)) continue;
      if (RegExp(r'^[pPiI]').hasMatch(t.substring(m.end))) continue;
      if (const {'480', '576', '720', '1080', '2160', '4320'}.contains(raw)) {
        continue;
      }
      final v = int.tryParse(raw);
      if (v != null && v > 0) return v;
    }
    return null;
  }
}

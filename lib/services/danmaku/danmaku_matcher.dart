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
  static String fromEpisode({
    required String name,
    String seriesName = '',
    int season = 0,
    int number = 0,
  }) {
    final series = seriesName.trim();
    if (season > 0 && number > 0 && series.isNotEmpty) {
      return '$series.'
          'S${season.toString().padLeft(2, '0')}'
          'E${number.toString().padLeft(2, '0')}';
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
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  /// 从集标题提取集号：支持「第N话/話/集/回/期」「EP/E + 数字」及
  /// 以数字开头的标题（`01 – 标题`）；提取不到返回 null。
  static int? parseEpisodeNumber(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final cn = RegExp(r'第\s*(\d+)\s*[话話集回期]').firstMatch(t);
    if (cn != null) return int.tryParse(cn.group(1)!);
    final ep = RegExp(r'(?:EP|E)\s*(\d+)', caseSensitive: false).firstMatch(t);
    if (ep != null) return int.tryParse(ep.group(1)!);
    final bare = RegExp(r'^(\d+)\b').firstMatch(t);
    if (bare != null) return int.tryParse(bare.group(1)!);
    return null;
  }
}

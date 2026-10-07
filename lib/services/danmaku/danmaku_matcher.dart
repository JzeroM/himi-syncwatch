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
}

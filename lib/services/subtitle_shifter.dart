/// 字幕时间轴偏移工具（纯 Dart，无 IO，便于单测）。
///
/// 正值 = 字幕延后显示，负值 = 提前；偏移后小于 0 的时间戳钳到 0
/// （FFmpeg 外挂轨不显示负时间）。SRT 时间轴格式 `00:00:01,500 --> …`，
/// ASS `Dialogue:` 行起止字段为 `0:00:01.00`（厘秒）。
class SubtitleShifter {
  const SubtitleShifter._();

  /// SRT 时间戳（`hh:mm:ss,mmm`，兼容 `.` 毫秒分隔）+ 箭头 + 结束时间。
  static final RegExp _srtArrow = RegExp(
    r'(\d{1,3}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,3}:\d{2}:\d{2}[,.]\d{1,3})',
  );

  /// ASS 时间戳（`h:mm:ss.cc`，小时不限位数）。
  static final RegExp _assTime = RegExp(r'^(\d+):(\d{2}):(\d{2})\.(\d{1,2})$');

  /// 时间戳上限 99:59:59,999，防溢出。
  static const int _maxMs = 100 * 3600 * 1000 - 1;

  /// 按内容自动分派：含 `Dialogue:`/`[Events]` 视为 ASS，否则 SRT
  /// （VTT 的 `.` 毫秒分隔与坐标后缀被 SRT 分支兼容处理）。
  static String shift(String text, int deltaMs) {
    if (deltaMs == 0) return text;
    return looksLikeAss(text)
        ? shiftAss(text, deltaMs)
        : shiftSrt(text, deltaMs);
  }

  /// 是否 ASS/SSA 文本。
  static bool looksLikeAss(String text) =>
      text.contains('Dialogue:') || text.contains('[Events]');

  /// 偏移 SRT（或 VTT）文本的起止时间；索引号、空行、坐标后缀原样保留。
  static String shiftSrt(String text, int deltaMs) {
    if (deltaMs == 0) return text;
    return text
        .split('\n')
        .map((line) => line.replaceAllMapped(_srtArrow, (m) {
              final start = _shiftSrtToken(m[1]!, deltaMs);
              final end = _shiftSrtToken(m[2]!, deltaMs);
              return '$start --> $end';
            }))
        .join('\n');
  }

  /// 偏移 ASS/SSA 文本 `Dialogue:` 行的起止字段；
  /// 其余行（`[Events]`/`Format:` 等）与行内其余逗号字段原样保留。
  static String shiftAss(String text, int deltaMs) {
    if (deltaMs == 0) return text;
    return text.split('\n').map((line) {
      const prefix = 'Dialogue:';
      final trimmed = line.trimRight();
      if (!trimmed.startsWith(prefix)) return line;
      final rest = trimmed.substring(prefix.length);
      final fields = rest.split(',');
      if (fields.length < 3) return line;
      fields[1] = _shiftAssToken(fields[1], deltaMs);
      fields[2] = _shiftAssToken(fields[2], deltaMs);
      return '$prefix${fields.join(',')}';
    }).join('\n');
  }

  /// 偏移单个 SRT 时间戳 token（`hh:mm:ss,mmm` / `.` 分隔）。
  /// 毫秒位统一输出 3 位（SRT/VTT 均合法）；格式不匹配原样返回。
  static String _shiftSrtToken(String token, int deltaMs) {
    final parts = token.split(':');
    if (parts.length != 3) return token;
    final sep = token.contains('.') ? '.' : ',';
    final secAndMs = parts[2].split(sep);
    if (secAndMs.length != 2) return token;
    final msStr = secAndMs[1];
    final msRaw = int.tryParse(msStr);
    if (msRaw == null) return token;
    // 毫秒按位权归一：'5'（1位）→ 500ms，'50' → 50ms，'500' → 500ms
    final msLen = msStr.length.clamp(1, 3);
    final ms = msLen == 1
        ? msRaw * 100
        : msLen == 2
            ? msRaw * 10
            : msRaw;
    final base = _parse(parts[0]) * 3600000 +
        _parse(parts[1]) * 60000 +
        _parse(secAndMs[0]) * 1000 +
        ms;
    final shifted = _clamp(base + deltaMs);
    return '${_pad(shifted ~/ 3600000, 2)}:'
        '${_pad((shifted ~/ 60000) % 60, 2)}:'
        '${_pad((shifted ~/ 1000) % 60, 2)}'
        '$sep${_pad(shifted % 1000, 3)}';
  }

  /// 偏移单个 ASS 时间戳 token（`h:mm:ss.cc`）；格式不匹配原样返回。
  static String _shiftAssToken(String token, int deltaMs) {
    final m = _assTime.firstMatch(token.trim());
    if (m == null) return token;
    final base = _parse(m[1]!) * 3600000 +
        _parse(m[2]!) * 60000 +
        _parse(m[3]!) * 1000 +
        _parse(m[4]!) * 10;
    final shifted = _clamp(base + deltaMs);
    return '${shifted ~/ 3600000}:'
        '${_pad((shifted ~/ 60000) % 60, 2)}:'
        '${_pad((shifted ~/ 1000) % 60, 2)}.'
        '${_pad((shifted % 1000) ~/ 10, 2)}';
  }

  static int _parse(String s) => int.tryParse(s) ?? 0;

  static int _clamp(int ms) => ms < 0 ? 0 : (ms > _maxMs ? _maxMs : ms);

  static String _pad(int v, int width) => v.toString().padLeft(width, '0');
}

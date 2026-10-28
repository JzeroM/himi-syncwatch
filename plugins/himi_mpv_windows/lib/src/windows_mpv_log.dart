import 'dart:io';

/// Windows MPV 崩溃诊断日志。
///
/// 使用同步追加写，避免 LogService 异步/并发写导致的截断与丢失；
/// 不记录 URL query/token，调用方应先脱敏。
class WindowsMpvLog {
  const WindowsMpvLog._();

  static final File _file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}himi_mpv_windows.log',
  );

  static void write(String tag, String message) {
    try {
      final line = '[${DateTime.now().toIso8601String()}][$tag] $message\n';
      _file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // 日志不可用不能影响播放。
    }
  }
}

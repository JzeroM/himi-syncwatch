import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  static const int _maxLogs = 1000;
  final List<String> _logs = [];
  final DateFormat _fmt = DateFormat('HH:mm:ss.SSS');

  // 实时落盘：进程闪退时内存日志丢失，追加写入 himi_runtime.log 保留现场
  File? _runtimeFile;
  Future<void>? _runtimeInit;

  /// 文件就绪前的日志缓冲（643）。
  ///
  /// `getTemporaryDirectory()` 是异步的，首个 log 调用时 `_runtimeFile`
  /// 还是 null。旧实现直接丢弃这些行；这里先缓存，就绪后一次性补写，
  /// 保证启动早期（最容易崩的阶段）的日志不丢。
  final List<String> _pendingRuntimeLines = [];

  List<String> get entries => List.unmodifiable(_logs);

  void log(String tag, String message) {
    final time = _fmt.format(DateTime.now());
    final entry = '[$time][$tag] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) _logs.removeAt(0);
    // ignore: avoid_print
    print(entry);
    _appendToRuntime(entry);
  }

  /// 追加一行到运行时日志（643：改为**同步**写）。
  ///
  /// 【真机教训】原实现用 `writeAsString`（异步且不 await）：原生访问违例
  /// （0xc0000005）会让进程**立即终止**，缓冲区里未落盘的日志全部丢失。
  /// 实测闪退前 75 分钟只留下 1 行日志，完全无法定位崩溃点。
  ///
  /// 同步写每次有 syscall 开销，但日志量很小（正常使用每分钟几条），
  /// 换取「崩溃现场必定可取证」是值得的。
  void _appendToRuntime(String entry) {
    final file = _runtimeFile;
    if (file == null) {
      // 文件尚未就绪：先缓存，`_initRuntimeFile` 完成后补写。
      _pendingRuntimeLines.add(entry);
      _runtimeInit ??= _initRuntimeFile();
      return;
    }
    _writeRuntimeLine(file, entry);
  }

  void _writeRuntimeLine(File file, String entry) {
    try {
      file.writeAsStringSync('$entry\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 落盘失败不能影响主流程（磁盘满 / 权限）。
    }
  }

  Future<void> _initRuntimeFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/himi_runtime.log');
      _runtimeFile = file;
      // 补写就绪前缓存的日志（保持原始顺序）。
      if (_pendingRuntimeLines.isNotEmpty) {
        final buffered = List<String>.of(_pendingRuntimeLines);
        _pendingRuntimeLines.clear();
        try {
          file.writeAsStringSync(
            '${buffered.join('\n')}\n',
            mode: FileMode.append,
            flush: true,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  String exportAll() => _logs.join('\n');

  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/himi_logs.log');
    return file.writeAsString(exportAll());
  }

  Future<void> shareLogs() async {
    final file = await exportToFile();
    if (Platform.operatingSystem == 'ohos') return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'HIMI 运行日志'),
    );
  }

  void clear() => _logs.clear();
}

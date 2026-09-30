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

  void _appendToRuntime(String entry) {
    _runtimeInit ??= _initRuntimeFile();
    _runtimeInit!.then(
      (_) {
        _runtimeFile?.writeAsString('$entry\n', mode: FileMode.append);
      },
      onError: (_) {},
    );
  }

  Future<void> _initRuntimeFile() async {
    final dir = await getTemporaryDirectory();
    _runtimeFile = File('${dir.path}/himi_runtime.log');
  }

  String exportAll() => _logs.join('\n');

  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/himi_logs.log');
    return file.writeAsString(exportAll());
  }

  Future<void> shareLogs() async {
    final file = await exportToFile();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'HIMI 运行日志'),
    );
  }

  void clear() => _logs.clear();
}

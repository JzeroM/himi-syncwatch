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

  List<String> get entries => List.unmodifiable(_logs);

  void log(String tag, String message) {
    final time = _fmt.format(DateTime.now());
    final entry = '[$time][$tag] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) _logs.removeAt(0);
    // ignore: avoid_print
    print(entry);
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

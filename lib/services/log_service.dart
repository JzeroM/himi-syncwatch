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
  ///
  /// 682：与 [_runtimeBuffer] 合并——不再单独维护，避免两套缓冲重复。
  final List<String> _runtimeBuffer = [];

  /// 682：是否已有异步写盘任务在飞（单飞，防高频日志堆积成 IO 风暴）。
  bool _runtimeFlushing = false;

  List<String> get entries => List.unmodifiable(_logs);

  /// [sync] 为 true 时同步落盘（仅低频关键节点使用，见 [flushSync]）。
  void log(String tag, String message, {bool sync = false}) {
    final time = _fmt.format(DateTime.now());
    final entry = '[$time][$tag] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) _logs.removeAt(0);
    // 用 stdout 而非 print：print 会被 _installErrorHooks 的兜底覆写回
    // LogService.log → 死循环；stdout.writeln 直写控制台不回环。
    stdout.writeln(entry);
    _appendToRuntime(entry);
    if (sync) flushSync();
  }

  /// 694：把缓冲**同步**落盘（进程 native 崩溃取证用）。
  ///
  /// 【为什么需要】`_scheduleRuntimeFlush` 是异步批量（16ms 合帧）：
  /// native SIGSEGV（引擎切换闪退）进程直接死，没来得及异步写的最后
  /// 一批日志全丢——真机 himi_logs 只剩启动段的根因之一。
  ///
  /// 【为什么不全量同步】643 教训：高频日志每条 open+write+fsync 会堵
  /// 主线程（Windows Application Hang）。`writeAsStringSync` 不 fsync，
  /// 进程崩溃不影响内核页缓存，单次毫秒级；只在**引擎切换/重载步骤、
  /// 崩溃钩子、黑屏定性快照**等低频关键节点调用。
  void flushSync() {
    if (_runtimeBuffer.isEmpty) return;
    final file = _runtimeFile;
    if (file == null) {
      // 文件尚未就绪：触发初始化，缓冲留给就绪后的批量写。
      _runtimeInit ??= _initRuntimeFile();
      return;
    }
    final batch = List<String>.of(_runtimeBuffer);
    _runtimeBuffer.clear();
    try {
      file.writeAsStringSync('${batch.join('\n')}\n', mode: FileMode.append);
    } catch (_) {
      // 写失败回插缓冲头，后续异步 flush 重试，不丢日志。
      _runtimeBuffer.insertAll(0, batch);
    }
  }

  /// 追加一行到运行时日志（682：改为**异步批量**落盘）。
  ///
  /// 【643 原方案的问题】当时改成 `writeAsStringSync(flush: true)`——
  /// 每次日志都在 **UI 线程**同步 open + write + **fsync**。日志量小时
  /// 没事，但房间模式拖动窗口时 Qt 每 80ms 回一帧 `windowMoved`，Dart
  /// 侧跟随 + `setBounds` 又会连带多次日志 → fsync 在主线程排队累积，
  /// 秒级卡死，最终被 Windows 判定 **Application Hang**（真机：
  /// 「进房间时 / 单人移动播放器窗口时无响应」，Qt 视频还在放、Flutter
  /// 面板窗不响应 = 主线程被同步 IO 堵住）。
  ///
  /// 【现在】内存缓冲 + 单飞异步 flush：
  ///   - 日志先进 `_runtimeBuffer`（纯内存，零开销）
  ///   - 只有缓冲非空且没有在飞任务时才起一次异步写
  ///   - 写盘期间新增的日志留在缓冲里，等下一轮批量带走
  ///
  /// 取舍：进程被强杀时，最多丢掉「正在写的那一批」（通常是最后几十毫秒
  /// 的日志），换来主线程永不被 IO 阻塞。崩溃现场依然可取证——因为崩溃
  /// 前的日志绝大多数已经在前几轮 flush 里落盘了。
  void _appendToRuntime(String entry) {
    _runtimeBuffer.add(entry);
    // 文件尚未就绪：`_initRuntimeFile` 完成后会一起补写。
    if (_runtimeFile == null) {
      _runtimeInit ??= _initRuntimeFile();
      return;
    }
    _scheduleRuntimeFlush();
  }

  /// 单飞调度：同一时刻最多一个异步写盘任务在飞。
  void _scheduleRuntimeFlush() {
    if (_runtimeFlushing) return;
    final file = _runtimeFile;
    if (file == null || _runtimeBuffer.isEmpty) return;
    _runtimeFlushing = true;
    // 每 16ms 让出一帧：批量合并同一帧内的多条日志，进一步降频。
    Future<void>.delayed(const Duration(milliseconds: 16), () {
      final batch = List<String>.of(_runtimeBuffer);
      _runtimeBuffer.clear();
      if (batch.isEmpty) {
        _runtimeFlushing = false;
        return;
      }
      // 异步写：不阻塞 UI 线程（`writeAsString` 走 IO 事件循环）。
      file
          .writeAsString('${batch.join('\n')}\n',
              mode: FileMode.append, flush: true)
          .catchError((Object _) => file)
          .whenComplete(() {
        _runtimeFlushing = false;
        // 写盘期间又有新日志 → 继续下一轮。
        if (_runtimeBuffer.isNotEmpty) _scheduleRuntimeFlush();
      });
    });
  }

  Future<void> _initRuntimeFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/himi_runtime.log');
      // 跨会话只增不减：超限裁剪保尾，防无限膨胀（分享/导出会失败）。
      await trimRuntimeFile(file);
      _runtimeFile = file;
      // 就绪前缓存的日志已并入 `_runtimeBuffer`，这里直接触发一次批量写。
      if (_runtimeBuffer.isNotEmpty) _scheduleRuntimeFlush();
    } catch (_) {}
  }

  /// 运行时日志裁剪：超过 [maxBytes] 时保尾 [keepBytes]（按行对齐），
  /// 文件头留一行裁剪标记。纯文件操作，可单测。
  static Future<void> trimRuntimeFile(
    File file, {
    int maxBytes = 8 * 1024 * 1024,
    int keepBytes = 4 * 1024 * 1024,
  }) async {
    try {
      if (!await file.exists()) return;
      if (await file.length() <= maxBytes) return;
      final content = await file.readAsString();
      if (content.length <= keepBytes) return;
      var kept = content.substring(content.length - keepBytes);
      // 按行对齐：丢掉半行残缺头部。
      final cut = kept.indexOf('\n');
      if (cut >= 0 && cut + 1 < kept.length) kept = kept.substring(cut + 1);
      await file.writeAsString('[himi_logs] 早期日志已裁剪（保尾 $keepBytes 字符）\n$kept');
    } catch (_) {}
  }

  /// 测试注入：把运行时文件指到临时文件（绕开 path_provider）。
  void debugAttachRuntimeFile(File file) {
    _runtimeFile = file;
    // 换文件后旧的 in-flight flush 目标不变也无害（追加写）；
    // 缓冲就地补写到新文件。
    if (_runtimeBuffer.isNotEmpty) _scheduleRuntimeFlush();
  }

  /// 694：收集**全部**日志（查根因用）——
  ///
  /// 【导出只剩 5 行的根因】旧 [exportToFile] 只导出内存环 [_logs]：
  /// 引擎切换闪退后重启 app 再导出，环里只剩**新会话**的启动段——
  /// 崩溃会话的现场全在跨会话追加的 himi_runtime.log 里，却没被导出。
  ///
  /// 现在：先 [flushSync] 收尾缓冲，再取 himi_runtime.log 全量
  /// （含历史会话）；文件不可用时退回内存环。
  Future<String> collectFullLog() async {
    flushSync();
    final file = _runtimeFile;
    final sb = StringBuffer();
    if (file != null) {
      try {
        if (await file.exists()) sb.write(await file.readAsString());
      } catch (_) {}
    }
    if (sb.isEmpty) sb.write(_logs.join('\n'));
    return sb.toString();
  }

  String exportAll() => _logs.join('\n');

  Future<File> exportToFile() async {
    final content = await collectFullLog();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/himi_logs.log');
    return file.writeAsString(content);
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

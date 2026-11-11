import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:himi_syncwatch/services/log_service.dart';

/// 656：Qt 播放器窗口的通信客户端（TCP localhost）。
///
/// 【为什么不用命名管道】最初设计用 Windows `CreateNamedPipe`，但
/// **Dart 无法连接命名管道**——`Socket.connect` 的
/// `InternetAddressType.unix` 只支持 Unix domain socket；命名管道必须走
/// `CreateFile`（原生 API），Dart 没有内置支持，得再写一个 Flutter 插件
/// 做桥接，复杂度不划算。
///
/// 改用 TCP：只绑 `127.0.0.1`，带一次性 token 校验。对局域网/公网
/// 不可见，安全性等价于命名管道。
///
/// 【协议】NDJSON（每帧一个 JSON + `\n`）：
///   Flutter → Qt：`{"type":"auth","token":...}` 首帧认证
///                 `{"type":"state","data":{...NativePlayerState...}}`
///   Qt → Flutter：`{"type":"command","data":{...NativePlayerCommand...}}`
class QtPlayerPipe {
  QtPlayerPipe._(this._socket, this._process, this.port);

  final Socket _socket;
  final Process _process;

  /// 实际使用的端口（调试用）。
  final int port;

  final StreamController<Map<String, Object?>> _commandController =
      StreamController<Map<String, Object?>>.broadcast();
  StreamSubscription<String>? _lineSub;
  bool _closed = false;

  /// 原生 → Dart 的命令流（`NativePlayerCommand` 的 JSON map）。
  Stream<Map<String, Object?>> get commands => _commandController.stream;

  /// 断开回调（Qt 进程退出/崩溃）。
  void Function()? onDisconnected;

  /// 671 A1：管道是否已断开（死适配器探测用）。
  bool get isClosed => _closed;

  /// 拉起 Qt 播放器并连接。
  ///
  /// @param exePath   `himi_qt_player.exe` 的绝对路径
  /// @param hdr       是否请求 HDR 直出
  /// @param hlg       内容是否为 HLG
  /// @param prewarm   隐藏待命模式（670：窗口收到 load 命令才显示，
  ///                  管道断开自动退出防孤儿进程）
  static Future<QtPlayerPipe> launch({
    required String exePath,
    required bool hdr,
    required bool hlg,
    bool prewarm = false,
  }) async {
    // 选一个空闲端口：绑 0 让系统分配，拿到端口后立即释放，再交给 Qt。
    // 有极小概率被抢占，但 Qt 侧 listen 失败会立即退出，上层重试即可。
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final token = _randomToken();
    final process = await Process.start(
      exePath,
      [
        '--port', '$port',
        '--token', token,
        '--hdr', hdr ? '1' : '0',
        '--hlg', hlg ? '1' : '0',
        // 676：父进程守卫——主窗口关闭/进程崩溃时 Qt 自己退出，
        // 不留孤儿播放窗（detached 进程不会随父进程退出）。
        '--parent-pid', '$pid',
        if (prewarm) '--prewarm',
      ],
      // 【必须用 detached，不能用 detachedWithStdio】
      //
      // `detachedWithStdio` 会给子进程创建 stdout/stderr 管道，但 Dart 侧
      // 从不读取（Qt 的 qInfo 日志没人消费）→ 管道缓冲区（约 4KB）写满 →
      // Qt 的 qInfo 阻塞 → 主线程卡死 → IPC 5 秒连不上 → Flutter 判定
      // 「启动失败」静默回退 646。
      //
      // 真机现象：任务管理器里完全看不到 himi_qt_player.exe，窗口仍是
      // 646 的原生窗口。
      //
      // 代价：看不到 Qt 侧日志。但关键状态（HDR 实际输出、播放位置等）
      // 都通过 IPC 回传，不影响功能。
      mode: ProcessStartMode.detached,
    );
    LogService().log('QtPlayer', 'Qt 进程已启动 pid=${process.pid} port=$port');

    // Qt 建监听需要一点时间（QTcpServer::listen 在 main 里同步执行，
    // 通常 < 300ms，含 Qt 自身初始化）。重试连接，最多 5 秒。
    Socket? socket;
    for (var attempt = 1; attempt <= 50; attempt++) {
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    if (socket == null) {
      process.kill();
      throw StateError('无法连接 Qt 播放器（127.0.0.1:$port）');
    }

    final pipe = QtPlayerPipe._(socket, process, port);
    // 首帧认证：Qt 侧要求第一帧必须是 auth，否则断开。
    socket.write('${jsonEncode({'type': 'auth', 'token': token})}\n');
    pipe._listen();
    return pipe;
  }

  static String _randomToken() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _listen() {
    _lineSub = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        try {
          final obj = jsonDecode(line) as Map<String, dynamic>;
          final type = obj['type'] as String?;
          if (type == 'command') {
            final data = obj['data'];
            if (data is Map) {
              _commandController.add(Map<String, Object?>.from(data));
            }
          }
        } catch (e) {
          LogService().log('QtPlayer', '管道 JSON 解析失败: $e');
        }
      },
      onDone: _handleDisconnect,
      onError: (Object e) {
        LogService().log('QtPlayer', '管道错误: $e');
        _handleDisconnect();
      },
      cancelOnError: true,
    );
  }

  void _handleDisconnect() {
    if (_closed) return;
    _closed = true;
    LogService().log('QtPlayer', '管道已断开');
    onDisconnected?.call();
    unawaited(_commandController.close());
  }

  /// 推送播放器状态给 Qt。
  ///
  /// [stateJson] 是 `NativePlayerState.toJson()` 的结果（87 字段）。
  /// 附带 `playUrl`：Qt 据此决定是否需要 `loadfile`（与上次相同则跳过）。
  void pushState(Map<String, Object?> stateJson, {String? playUrl}) {
    if (_closed) return;
    try {
      final frame = <String, Object?>{
        'type': 'state',
        'data': <String, Object?>{
          ...stateJson,
          if (playUrl != null && playUrl.isNotEmpty) 'playUrl': playUrl,
        },
      };
      _socket.write('${jsonEncode(frame)}\n');
    } catch (e) {
      LogService().log('QtPlayer', '推送状态失败: $e');
      _handleDisconnect();
    }
  }

  /// 发送一条控制命令给 Qt（Flutter → Qt 方向）。
  ///
  /// 与 [pushState] 的区别：state 是「状态快照」，command 是「动作指令」。
  /// Qt 侧对 command 的处理见 `main.cpp` 的 `commandReceived` 分支。
  void sendCommandRaw(Map<String, Object?> command) {
    if (_closed) return;
    try {
      final frame = <String, Object?>{
        'type': 'command',
        'data': command,
      };
      _socket.write('${jsonEncode(frame)}\n');
    } catch (e) {
      LogService().log('QtPlayer', '发送命令失败: $e');
      _handleDisconnect();
    }
  }

  /// 关闭连接并结束 Qt 进程。
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _lineSub?.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    try {
      _process.kill();
    } catch (_) {}
    try {
      await _commandController.close();
    } catch (_) {}
  }
}

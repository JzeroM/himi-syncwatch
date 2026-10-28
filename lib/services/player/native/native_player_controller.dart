import 'dart:async';

import 'native_player_command.dart';
import 'native_player_state.dart';

/// 原生命令执行器：由 PlayerScreen / MpvPlayerAdapter 注入。
typedef NativePlayerCommandHandler = Future<void> Function(
    NativePlayerCommand command);

/// 把权威状态推给原生宿主（平台通道）。
typedef NativePlayerPushFn = Future<void> Function(NativePlayerState state);

/// 打开原生宿主窗口（鸿蒙子窗口 / Android Dialog）。
typedef NativePlayerOpenFn = Future<void> Function(
    String platform, NativePlayerState initial);

/// 关闭原生宿主窗口。
typedef NativePlayerCloseFn = Future<void> Function();

/// 原生播放器 Dart 侧控制器（计划书 §4.3）。
///
/// 职责：
/// - `open/update/close` 生命周期，幂等（重复 open/close 不产生多个窗口）；
/// - 把 `NativePlayerState` 推给平台宿主，状态推送至少间隔
///   [minPushInterval]（默认 200ms），但暂停/seek/切换内容等
///   `requiresImmediatePush` 命令后的更新立即推送；
/// - 接收原生命令（`himi_mpv/native_ui/commands` /
///   `himi_native_player/commands`），解析为 [NativePlayerCommand]
///   并交给注入的执行器。
class NativePlayerController {
  NativePlayerController({
    NativePlayerOpenFn? onOpen,
    NativePlayerCloseFn? onClose,
    NativePlayerPushFn? onPush,
    NativePlayerCommandHandler? onCommand,
    this.minPushInterval = const Duration(milliseconds: 200),
    DateTime Function()? clock,
    void Function(String message)? log,
  })  : _onOpen = onOpen,
        _onClose = onClose,
        _onPush = onPush,
        _onCommand = onCommand,
        _clock = clock ?? DateTime.now,
        _log = log;

  /// 状态推送最小间隔（周期性轮询快照防抖）。
  final Duration minPushInterval;

  final NativePlayerOpenFn? _onOpen;
  final NativePlayerCloseFn? _onClose;
  final NativePlayerPushFn? _onPush;
  final NativePlayerCommandHandler? _onCommand;
  final DateTime Function() _clock;
  final void Function(String message)? _log;

  bool _open = false;
  String? _platform;
  NativePlayerState? _lastState;
  DateTime? _lastPushAt;
  NativePlayerState? _pendingState;
  Timer? _debounceTimer;
  StreamSubscription<Map<Object?, Object?>>? _commandSub;
  bool _pushInFlight = false;

  final StreamController<NativePlayerCommand> _commandCtrl =
      StreamController<NativePlayerCommand>.broadcast();

  /// 是否已打开原生 UI 会话。
  bool get isOpen => _open;

  /// 打开时的平台名（'android' / 'ohos'）；关闭后为 null。
  String? get platform => _platform;

  /// 最近一次推送的权威状态。
  NativePlayerState? get lastState => _lastState;

  /// 原生命令流（解析成功后广播；同时直接交给 [onCommand] 执行）。
  Stream<NativePlayerCommand> get commands => _commandCtrl.stream;

  /// 打开原生 UI。
  ///
  /// 幂等：已打开时只更新状态，不重复创建窗口。
  Future<void> open({
    required String platform,
    required NativePlayerState initial,
    NativePlayerOpenFn? onOpen,
    NativePlayerPushFn? onPush,
    NativePlayerCommandHandler? onCommand,
    Stream<Map<Object?, Object?>>? commandStream,
  }) async {
    _platform = platform;
    if (_open) {
      // 已打开：只同步状态，不重复建窗。
      _log?.call('NativePlayerController: open 幂等，仅更新状态');
      await update(initial, immediate: true);
      return;
    }
    _open = true;
    _lastState = initial;
    _lastPushAt = _clock();
    _pendingState = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final push = onPush ?? _onPush;
    if (push != null) {
      try {
        await push(initial);
      } catch (e) {
        _log?.call('NativePlayerController: 初始状态推送失败: $e');
      }
    }
    final openFn = onOpen ?? _onOpen;
    if (openFn != null) {
      try {
        await openFn(platform, initial);
      } catch (e) {
        _log?.call('NativePlayerController: 打开原生宿主失败: $e');
        _open = false;
        rethrow;
      }
    }
    if (commandStream != null) {
      attachCommandStream(commandStream, onCommand: onCommand);
    }
    _log?.call('NativePlayerController: open platform=$platform');
  }

  /// 关闭原生 UI。幂等：未打开时直接返回。
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _platform = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingState = null;
    await _commandSub?.cancel();
    _commandSub = null;
    final closeFn = _onClose;
    if (closeFn != null) {
      try {
        await closeFn();
      } catch (e) {
        _log?.call('NativePlayerController: 关闭原生宿主失败: $e');
      }
    }
    _log?.call('NativePlayerController: close');
  }

  /// 更新权威状态并推给原生宿主。
  ///
  /// [immediate] 为 true（或 [NativePlayerCommand.requiresImmediatePush]
  /// 命令执行后调用方显式传入）时跳过防抖立即推送；否则两次推送至少间隔
  /// [minPushInterval]，间隔内的更新合并为一次尾随推送（保留最新状态）。
  Future<void> update(NativePlayerState state, {bool immediate = false}) async {
    _lastState = state;
    if (!_open) return;
    final push = _onPush;
    if (push == null) return;

    final now = _clock();
    final last = _lastPushAt;
    if (immediate || last == null || now.difference(last) >= minPushInterval) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      await _doPush(push, state, now);
      return;
    }
    // 间隔内：合并为尾随推送，保留最新状态。
    _pendingState = state;
    _debounceTimer ??= Timer(minPushInterval - now.difference(last), () {
      _debounceTimer = null;
      final pending = _pendingState;
      _pendingState = null;
      if (pending == null || !_open) return;
      unawaited(_doPush(_onPush!, pending, _clock()));
    });
  }

  Future<void> _doPush(
    NativePlayerPushFn push,
    NativePlayerState state,
    DateTime now,
  ) async {
    if (_pushInFlight) return;
    _pushInFlight = true;
    try {
      _lastPushAt = now;
      await push(state);
    } catch (e) {
      _log?.call('NativePlayerController: 状态推送失败: $e');
    } finally {
      _pushInFlight = false;
    }
  }

  /// 订阅原生命令流（map 原始格式），解析后广播并交给执行器。
  ///
  /// 重复调用会替换旧订阅（幂等）。
  void attachCommandStream(
    Stream<Map<Object?, Object?>> stream, {
    NativePlayerCommandHandler? onCommand,
  }) {
    unawaited(_commandSub?.cancel());
    _commandSub = stream.listen(
      (raw) => handleNativeCommand(raw, onCommand: onCommand),
      onError: (Object e) =>
          _log?.call('NativePlayerController: 命令流错误: $e'),
    );
  }

  /// 解析并路由一条原生命令。未知 type 忽略。
  Future<void> handleNativeCommand(
    Map<Object?, Object?> raw, {
    NativePlayerCommandHandler? onCommand,
  }) async {
    final command = NativePlayerCommand.fromMap(raw);
    if (command == null) {
      _log?.call('NativePlayerController: 未知命令 $raw');
      return;
    }
    if (!_commandCtrl.isClosed) {
      _commandCtrl.add(command);
    }
    final handler = onCommand ?? _onCommand;
    if (handler != null) {
      try {
        await handler(command);
      } catch (e) {
        _log?.call('NativePlayerController: 命令执行失败 '
            '${command.runtimeType}: $e');
      }
    }
  }

  /// 释放（不关闭宿主窗口，仅清理流与定时器）。
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _commandSub?.cancel();
    _commandSub = null;
    await _commandCtrl.close();
  }
}

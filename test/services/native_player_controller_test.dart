import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_command.dart';
import 'package:himi_syncwatch/services/player/native/native_player_controller.dart';
import 'package:himi_syncwatch/services/player/native/native_player_state.dart';

void main() {
  group('NativePlayerController 生命周期', () {
    test('open 推送初始状态并创建宿主一次', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        var opens = 0;
        String? platform;
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async {
            opens++;
            platform = p;
          },
          onClose: () async {},
        );

        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();

        expect(controller.isOpen, isTrue);
        expect(opens, 1);
        expect(platform, 'android');
        expect(pushed, hasLength(1));
      });
    });

    test('open 幂等：重复 open 不重复建窗，只更新状态', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        var opens = 0;
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async => opens++,
          onClose: () async {},
        );

        controller.open(
            platform: 'ohos', initial: const NativePlayerState());
        async.flushMicrotasks();
        controller.open(
            platform: 'ohos',
            initial: const NativePlayerState(positionMs: 500));
        async.flushMicrotasks();

        expect(opens, 1);
        expect(pushed.last.positionMs, 500);
        expect(controller.isOpen, isTrue);
      });
    });

    test('close 幂等：重复 close 只销毁一次', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        var closes = 0;
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async {},
          onOpen: (p, s) async {},
          onClose: () async => closes++,
        );

        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();
        controller.close();
        async.flushMicrotasks();
        controller.close();
        async.flushMicrotasks();

        expect(closes, 1);
        expect(controller.isOpen, isFalse);
      });
    });

    test('未 open 时 update 不推送', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        var pushes = 0;
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushes++,
        );

        controller.update(const NativePlayerState(positionMs: 1),
            immediate: true);
        async.flushMicrotasks();

        expect(pushes, 0);
        // lastState 仍然记录（供 open 前缓存）。
        expect(controller.lastState?.positionMs, 1);
      });
    });
  });

  group('NativePlayerController 状态推送防抖', () {
    test('间隔内更新合并为一次尾随推送（保留最新）', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async {},
          onClose: () async {},
        );
        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();
        expect(pushed, hasLength(1)); // t=0 初始推送

        // t=50ms：间隔内更新 → 合并等待。
        async.elapse(const Duration(milliseconds: 50));
        controller.update(const NativePlayerState(positionMs: 100));
        // t=80ms：又一发 → pending 被最新覆盖。
        async.elapse(const Duration(milliseconds: 30));
        controller.update(const NativePlayerState(positionMs: 200));
        async.flushMicrotasks();
        expect(pushed, hasLength(1)); // 仍是初始推送

        // t=200ms：尾随推送触发（0+200ms），只推最新 pending。
        async.elapse(const Duration(milliseconds: 120));
        async.flushMicrotasks();
        expect(pushed, hasLength(2));
        expect(pushed.last.positionMs, 200);
      });
    });

    test('超过间隔的更新立即推送', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async {},
          onClose: () async {},
        );
        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 250));
        controller.update(const NativePlayerState(positionMs: 300));
        async.flushMicrotasks();
        expect(pushed, hasLength(2));
        expect(pushed.last.positionMs, 300);
      });
    });

    test('immediate 跳过防抖立即推送', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async {},
          onClose: () async {},
        );
        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 10));
        controller.update(const NativePlayerState(positionMs: 42),
            immediate: true);
        async.flushMicrotasks();
        expect(pushed, hasLength(2));
        expect(pushed.last.positionMs, 42);
      });
    });

    test('requiresImmediatePush 命令后的更新立即推送', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        final pushed = <NativePlayerState>[];
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async => pushed.add(s),
          onOpen: (p, s) async {},
          onClose: () async {},
        );
        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();

        // 模拟原生 seekTo → Dart 立即推权威状态（seek 语义 = 立即）。
        async.elapse(const Duration(milliseconds: 20));
        final seek = const SeekTo(positionMs: 99000);
        expect(seek.requiresImmediatePush, isTrue);
        controller.update(const NativePlayerState(positionMs: 99000),
            immediate: seek.requiresImmediatePush);
        async.flushMicrotasks();
        expect(pushed.last.positionMs, 99000);
      });
    });

    test('推送失败不影响后续推送', () {
      fakeAsync((async) {
        final epoch = DateTime(2026);
        var calls = 0;
        final controller = NativePlayerController(
          clock: () => epoch.add(async.elapsed),
          onPush: (s) async {
            calls++;
            if (calls == 2) throw StateError('bridge down');
          },
          onOpen: (p, s) async {},
          onClose: () async {},
          log: (_) {},
        );
        controller.open(
            platform: 'android', initial: const NativePlayerState());
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 250));
        controller.update(const NativePlayerState(positionMs: 1),
            immediate: true);
        async.flushMicrotasks();
        // 失败被捕获，不抛出；后续仍可继续。
        expect(controller.isOpen, isTrue);

        async.elapse(const Duration(milliseconds: 250));
        controller.update(const NativePlayerState(positionMs: 2),
            immediate: true);
        async.flushMicrotasks();
        expect(calls, 3);
      });
    });
  });

  group('NativePlayerController 命令路由', () {
    test('handleNativeCommand 解析并交给执行器，同时广播', () {
      fakeAsync((async) {
        final controller = NativePlayerController();
        final received = <NativePlayerCommand>[];
        final broadcast = <NativePlayerCommand>[];
        final sub = controller.commands.listen(broadcast.add);

        controller.handleNativeCommand(
          const {'type': 'seekTo', 'positionMs': 1234},
          onCommand: (c) async => received.add(c),
        );
        async.flushMicrotasks();

        expect(received, hasLength(1));
        expect(received.single, isA<SeekTo>());
        expect((received.single as SeekTo).positionMs, 1234);
        expect(broadcast, hasLength(1));

        unawaited(sub.cancel());
        unawaited(controller.dispose());
      });
    });

    test('构造注入的执行器兜底生效', () {
      fakeAsync((async) {
        final received = <NativePlayerCommand>[];
        final controller = NativePlayerController(
          onCommand: (c) async => received.add(c),
        );
        controller.handleNativeCommand(const {'type': 'togglePlay'});
        async.flushMicrotasks();
        expect(received.single, isA<TogglePlay>());
        unawaited(controller.dispose());
      });
    });

    test('未知命令忽略且不抛出', () {
      fakeAsync((async) {
        var called = 0;
        final controller = NativePlayerController(
          onCommand: (c) async => called++,
        );
        controller.handleNativeCommand(const {'type': 'wtf'});
        async.flushMicrotasks();
        expect(called, 0);
        unawaited(controller.dispose());
      });
    });

    test('执行器抛错被捕获', () {
      fakeAsync((async) {
        final controller = NativePlayerController(
          onCommand: (c) async => throw StateError('bad'),
          log: (_) {},
        );
        // 不应抛出。
        controller.handleNativeCommand(const {'type': 'togglePlay'});
        async.flushMicrotasks();
        expect(controller.isOpen, isFalse);
        unawaited(controller.dispose());
      });
    });

    test('attachCommandStream 订阅原始流并逐条路由', () {
      fakeAsync((async) {
        final source = StreamController<Map<Object?, Object?>>();
        final received = <NativePlayerCommand>[];
        final controller = NativePlayerController(
          onCommand: (c) async => received.add(c),
        );
        controller.attachCommandStream(source.stream);

        source.add(const {'type': 'requestBack'});
        source.add(const {'type': 'unknown-x'});
        source.add(const {'type': 'setVolume', 'volume': 0.9});
        async.flushMicrotasks();

        expect(received, hasLength(2));
        expect(received[0], isA<RequestBack>());
        expect(received[1], isA<SetVolume>());

        unawaited(source.close());
        unawaited(controller.dispose());
      });
    });
  });
}

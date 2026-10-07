import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/controls_auto_hide.dart';

void main() {
  late bool hidden;

  ControlsAutoHideController make({
    bool Function()? enabled,
    List<FocusNode> Function()? focusRoots,
  }) {
    hidden = false;
    return ControlsAutoHideController(
      after: const Duration(seconds: 5),
      onHide: () => hidden = true,
      focusRoots: focusRoots ?? () => const <FocusNode>[],
      enabled: enabled,
    );
  }

  group('计时触发与顺延', () {
    test('5 秒无操作触发 onHide', () {
      fakeAsync((async) {
        final c = make();
        c.reset();
        async.elapse(const Duration(seconds: 4));
        expect(hidden, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);
        c.dispose();
      });
    });

    test('reset 顺延：4 秒后重开一轮，第 5 秒才触发', () {
      fakeAsync((async) {
        final c = make();
        c.reset();
        async.elapse(const Duration(seconds: 4));
        c.reset();
        async.elapse(const Duration(seconds: 4));
        expect(hidden, isFalse, reason: '重开后未到 5 秒');
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);
        c.dispose();
      });
    });

    test('cancel 后不再触发', () {
      fakeAsync((async) {
        final c = make();
        c.reset();
        async.elapse(const Duration(seconds: 3));
        c.cancel();
        async.elapse(const Duration(seconds: 10));
        expect(hidden, isFalse);
        c.dispose();
      });
    });

    test('enabled=false 不启动；到点时已禁用不回调', () {
      fakeAsync((async) {
        var enabled = false;
        final c = make(enabled: () => enabled);
        c.reset();
        async.elapse(const Duration(seconds: 10));
        expect(hidden, isFalse, reason: '禁用时不启动计时');

        enabled = true;
        c.reset();
        async.elapse(const Duration(seconds: 4));
        enabled = false;
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isFalse, reason: '到点时控件已隐藏不回调');
        c.dispose();
      });
    });
  });

  group('指针操作（按住暂停/松手重开）', () {
    test('按下暂停计时，按住 60 秒不隐藏；松手重新起算 5 秒', () {
      fakeAsync((async) {
        final c = make();
        c.reset();
        async.elapse(const Duration(seconds: 4));
        c.notePointerDown();
        async.elapse(const Duration(seconds: 60));
        expect(hidden, isFalse, reason: '按住期间不隐藏');
        c.notePointerUp();
        async.elapse(const Duration(seconds: 4));
        expect(hidden, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);
        c.dispose();
      });
    });
  });

  group('焦点判定', () {
    test('根内焦点顺延；根外焦点不顺延（静置焦点不产生回调）', () {
      fakeAsync((async) {
        final root = FocusNode(debugLabel: 'root');
        final outsider = FocusNode(debugLabel: 'outsider');
        addTearDown(root.dispose);
        addTearDown(outsider.dispose);
        final c = make(focusRoots: () => [root]);

        // 焦点移到根上 → 顺延一轮
        c.reset();
        async.elapse(const Duration(seconds: 4));
        c.onFocusChanged(root);
        async.elapse(const Duration(seconds: 4));
        expect(hidden, isFalse, reason: '根内焦点变更顺延到 8 秒');
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);

        // 焦点在根外 → 不顺延，原计时照走到点
        hidden = false;
        c.reset();
        async.elapse(const Duration(seconds: 4));
        c.onFocusChanged(outsider);
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue, reason: '根外焦点不产生顺延');

        // 空焦点安全
        hidden = false;
        c.reset();
        async.elapse(const Duration(seconds: 4));
        c.onFocusChanged(null);
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);
        c.dispose();
      });
    });

    testWidgets('containsFocus：根自身/后代命中，外部不命中', (tester) async {
      final root = FocusNode(debugLabel: 'root');
      final child = FocusNode(debugLabel: 'child');
      final outsider = FocusNode(debugLabel: 'outsider');
      addTearDown(root.dispose);
      addTearDown(child.dispose);
      addTearDown(outsider.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            Focus(
              focusNode: root,
              child: Focus(focusNode: child, child: const SizedBox()),
            ),
            Focus(focusNode: outsider, child: const SizedBox()),
          ],
        ),
      ));

      expect(ControlsAutoHideController.containsFocus(root, root), isTrue,
          reason: '根自身命中');
      expect(ControlsAutoHideController.containsFocus(root, child), isTrue,
          reason: '后代焦点命中（ancestors 链）');
      expect(ControlsAutoHideController.containsFocus(root, outsider), isFalse);
      expect(ControlsAutoHideController.containsFocus(root, null), isFalse);
    });
  });

  group('按键事件', () {
    test('onKeyEvent 不消费事件，仅顺延计时', () {
      fakeAsync((async) {
        final root = FocusNode(debugLabel: 'root');
        addTearDown(root.dispose);
        final c = make();

        c.reset();
        async.elapse(const Duration(seconds: 4));
        final result = c.onKeyEvent(
          root,
          KeyDownEvent(
            timeStamp: Duration.zero,
            logicalKey: LogicalKeyboardKey.enter,
            physicalKey: PhysicalKeyboardKey.enter,
          ),
        );
        expect(result, KeyEventResult.ignored, reason: '不消费，继续冒泡');
        async.elapse(const Duration(seconds: 4));
        expect(hidden, isFalse, reason: '按键顺延到 9 秒');
        async.elapse(const Duration(seconds: 1));
        expect(hidden, isTrue);
        c.dispose();
      });
    });
  });
}

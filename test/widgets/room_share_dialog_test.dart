import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/room/room_share_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 二维码卡片的位置（590：弹窗自持 RepaintBoundary 的 key，测试改用
/// QrImageView 定位——与 Flutter 侧实现解耦，不再需要外部传 key）。
Finder _qrFinder() => find.byType(QrImageView);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  Future<void> Function(Uint8List?)? onShareQr,
  Future<void> Function(Uint8List?)? onSaveQr,
  Future<void> Function()? onCopyCode,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RoomShareDialog(
                  roomCode: 'ROOM-1234',
                  onShareQr: onShareQr ?? (_) async {},
                  onSaveQr: onSaveQr ?? (_) async {},
                  onCopyCode: onCopyCode ?? () async {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽屏为左二维码右操作双栏', (tester) async {
    await _pump(tester);

    expect(find.text('分享加入房间'), findsOneWidget);
    expect(find.text('分享二维码'), findsOneWidget);
    expect(find.text('保存二维码'), findsOneWidget);
    expect(find.text('复制房间码'), findsOneWidget);
    expect(find.text('ROOM-1234'), findsNothing);

    final qrRect = tester.getRect(_qrFinder());
    final primaryRect =
        tester.getRect(find.byKey(const ValueKey('roomSharePrimary')));
    final saveRect =
        tester.getRect(find.byKey(const ValueKey('roomShareSave')));
    final copyRect =
        tester.getRect(find.byKey(const ValueKey('roomShareCopy')));

    expect(qrRect.center.dx, lessThan(primaryRect.center.dx));
    expect(primaryRect.top, lessThan(saveRect.top));
    expect(saveRect.top, lessThan(copyRect.top));
  });

  testWidgets('窄屏纵向排列且不溢出', (tester) async {
    await _pump(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    final qrRect = tester.getRect(_qrFinder());
    final primaryRect =
        tester.getRect(find.byKey(const ValueKey('roomSharePrimary')));
    expect(primaryRect.top, greaterThan(qrRect.bottom));
  });

  testWidgets('横屏小高度可滚动且不溢出', (tester) async {
    await _pump(tester, size: const Size(640, 360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('动作完成前保持弹窗并禁用关闭', (tester) async {
    final completer = Completer<void>();
    var called = false;
    await _pump(
      tester,
      onShareQr: (_) {
        called = true;
        return completer.future;
      },
    );

    // 截图走 RepaintBoundary.toImage（真实光栅化），必须用 runAsync 让
    // 真实异步推进；否则 FakeAsync 下 future 永不完成。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('roomSharePrimary')));
      await tester.pump();
      // 2s 超时兜底后回调才执行（测试环境 toImage 不会真正完成）。
      await Future<void>.delayed(const Duration(milliseconds: 2200));
    });
    await tester.pump();

    expect(called, isTrue);
    expect(find.byType(RoomShareDialog), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('roomShareClose')))
          .onPressed,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('roomShareClose')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byType(RoomShareDialog), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RoomShareDialog), findsNothing);
  });

  testWidgets('保存与复制回调执行后关闭弹窗', (tester) async {
    var saves = 0;
    var copies = 0;
    await _pump(
      tester,
      onSaveQr: (_) async {
        saves++;
      },
      onCopyCode: () async {
        copies++;
      },
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('roomShareSave')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
    });
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byType(RoomShareDialog), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roomShareCopy')));
    await tester.pumpAndSettle();
    expect(copies, 1);
    expect(find.byType(RoomShareDialog), findsNothing);
  });

  testWidgets('关闭按钮可关闭弹窗', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('roomShareClose')));
    await tester.pumpAndSettle();

    expect(find.byType(RoomShareDialog), findsNothing);
  });
}

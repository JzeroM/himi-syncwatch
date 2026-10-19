import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/room/room_share_dialog.dart';

Future<void> _pump(
  WidgetTester tester, {
  required GlobalKey qrKey,
  Size size = const Size(1200, 800),
  Future<void> Function()? onShareQr,
  Future<void> Function()? onSaveQr,
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
                  qrKey: qrKey,
                  onShareQr: onShareQr ?? () async {},
                  onSaveQr: onSaveQr ?? () async {},
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
    final qrKey = GlobalKey();
    await _pump(tester, qrKey: qrKey);

    expect(find.text('分享加入房间'), findsOneWidget);
    expect(find.text('分享二维码'), findsOneWidget);
    expect(find.text('保存二维码'), findsOneWidget);
    expect(find.text('复制房间码'), findsOneWidget);
    expect(find.text('ROOM-1234'), findsNothing);

    final qrRect = tester.getRect(find.byKey(qrKey));
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
    final qrKey = GlobalKey();
    await _pump(tester, qrKey: qrKey, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    final qrRect = tester.getRect(find.byKey(qrKey));
    final primaryRect =
        tester.getRect(find.byKey(const ValueKey('roomSharePrimary')));
    expect(primaryRect.top, greaterThan(qrRect.bottom));
  });

  testWidgets('横屏小高度可滚动且不溢出', (tester) async {
    final qrKey = GlobalKey();
    await _pump(tester, qrKey: qrKey, size: const Size(640, 360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('动作完成前保持弹窗并禁用关闭', (tester) async {
    final qrKey = GlobalKey();
    final completer = Completer<void>();
    var called = false;
    await _pump(
      tester,
      qrKey: qrKey,
      onShareQr: () {
        called = true;
        return completer.future;
      },
    );

    await tester.tap(find.byKey(const ValueKey('roomSharePrimary')));
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
    final qrKey = GlobalKey();
    var saves = 0;
    var copies = 0;
    await _pump(
      tester,
      qrKey: qrKey,
      onSaveQr: () async {
        saves++;
      },
      onCopyCode: () async {
        copies++;
      },
    );

    await tester.tap(find.byKey(const ValueKey('roomShareSave')));
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
    final qrKey = GlobalKey();
    await _pump(tester, qrKey: qrKey);

    await tester.tap(find.byKey(const ValueKey('roomShareClose')));
    await tester.pumpAndSettle();

    expect(find.byType(RoomShareDialog), findsNothing);
  });
}

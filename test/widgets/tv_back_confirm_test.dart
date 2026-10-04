import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/tv/tv_back_confirm.dart';

/// 注入可控时间源：测试手动推进验证 2 秒窗口过期。
DateTime _now = DateTime(2026, 1, 1, 12);

Widget _harness({
  required bool enabled,
  required Future<void> Function() onConfirm,
  String confirmText = '再按一次退出播放器',
}) =>
    MaterialApp(
      home: TvBackConfirm(
        enabled: enabled,
        onConfirm: onConfirm,
        confirmText: confirmText,
        now: () => _now,
        child: const Scaffold(body: Center(child: Text('body'))),
      ),
    );

void main() {
  int confirmed = 0;

  setUp(() {
    confirmed = 0;
    _now = DateTime(2026, 1, 1, 12);
  });

  testWidgets('TV 首按返回仅提示，不执行退出', (tester) async {
    await tester.pumpWidget(_harness(
      enabled: true,
      onConfirm: () async => confirmed++,
    ));

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('再按一次退出播放器'), findsOneWidget);
    expect(confirmed, 0, reason: '首按不退出');
  });

  testWidgets('TV 窗口内第二按执行退出', (tester) async {
    await tester.pumpWidget(_harness(
      enabled: true,
      onConfirm: () async => confirmed++,
    ));

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(confirmed, 0);

    _now = _now.add(const Duration(seconds: 1)); // 窗口内
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(confirmed, 1, reason: '窗口内第二按退出');
  });

  testWidgets('TV 窗口过期重新计时：第三按才执行退出', (tester) async {
    await tester.pumpWidget(_harness(
      enabled: true,
      onConfirm: () async => confirmed++,
    ));

    // 第一按：提示
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(confirmed, 0);

    // 过期后再按：重新提示，不退出
    _now = _now.add(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(confirmed, 0, reason: '窗口已过期，视为新的首按');
    expect(find.text('再按一次退出播放器'), findsOneWidget);

    // 窗口内再按：退出
    _now = _now.add(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(confirmed, 1, reason: '过期重计后窗口内第二按退出');
  });

  testWidgets('非 TV：返回直接执行退出，无提示', (tester) async {
    await tester.pumpWidget(_harness(
      enabled: false,
      onConfirm: () async => confirmed++,
    ));

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(confirmed, 1, reason: '非 TV 直接确认（平台默认流程）');
    expect(find.text('再按一次退出播放器'), findsNothing);
  });

  testWidgets('确认文案可自定义', (tester) async {
    await tester.pumpWidget(_harness(
      enabled: true,
      confirmText: '再按一次返回退出应用',
      onConfirm: () async => confirmed++,
    ));

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('再按一次返回退出应用'), findsOneWidget);
    expect(find.text('再按一次退出播放器'), findsNothing);
  });
}

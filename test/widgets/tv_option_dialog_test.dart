import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_option_dialog.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

import '../helpers/test_fakes.dart';

/// showTvOptionDialog 组件测试：居中弹层、TV 方向键上下切换（RadioGroup
/// 劫持回归）、autofocus 落焦当前值、非 TV 点选、选中回调与关闭。
void main() {
  const options = [
    TvOptionEntry<String>(value: 'a', label: '甲', key: Key('opt_a')),
    TvOptionEntry<String>(value: 'b', label: '乙', subtitle: '乙说明', key: Key('opt_b')),
    TvOptionEntry<String>(value: 'c', label: '丙', key: Key('opt_c')),
  ];

  Future<void> pumpHost(
    WidgetTester tester, {
    required void Function(BuildContext) open,
    bool tvMode = true,
    bool remote = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(AppSettings(tvMode: tvMode)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final page = MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: remote && tvMode ? TvRemoteShell(child: page) : page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester, {String current = 'a'}) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('opt_a')), findsOneWidget);
    expect(find.byKey(const Key('opt_b')), findsOneWidget);
    expect(find.byKey(const Key('opt_c')), findsOneWidget);
    expect(current, isNotEmpty);
  }

  testWidgets('居中 AlertDialog，不用 BottomSheet', (tester) async {
    String? selected;
    await pumpHost(
      tester,
      open: (ctx) => showTvOptionDialog<String>(
        context: ctx,
        title: '选择',
        currentValue: 'a',
        onSelected: (v) => selected = v,
        options: options,
      ),
    );
    await openDialog(tester);

    // AlertDialog 在屏幕中心附近
    final rect = tester.getRect(find.byType(AlertDialog));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(rect.center.dy, closeTo(screen.height / 2, 40));
    expect(find.byType(BottomSheet), findsNothing);
    expect(selected, isNull);
  });

  testWidgets('TV：当前值行 autofocused；方向键上下移动弹层不关闭；Enter 选择',
      (tester) async {
    String? selected;
    await pumpHost(
      tester,
      open: (ctx) => showTvOptionDialog<String>(
        context: ctx,
        title: '选择',
        currentValue: 'a',
        onSelected: (v) => selected = v,
        options: options,
      ),
    );
    await openDialog(tester);

    // 打开即落焦当前值行
    final rowA = tester.widget<TvFocusable>(find.byKey(const Key('opt_a')));
    expect(rowA.autofocus, isTrue);
    expect(
      find
          .descendant(
            of: find.byKey(const Key('opt_a')),
            matching: find.byType(Icon),
          )
          .evaluate()
          .isNotEmpty,
      isTrue,
      reason: '当前值行有对勾',
    );

    // 方向键下移：弹层不关闭、无选择回调（RadioGroup 劫持回归）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget, reason: '方向键不应关闭弹层');
    expect(selected, isNull, reason: '方向键不应触发选择');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Enter 选中第 3 项
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'c');
    expect(find.byType(AlertDialog), findsNothing, reason: '选中后关闭');
  });

  testWidgets('TV：点选行 → 回调并关闭', (tester) async {
    String? selected;
    await pumpHost(
      tester,
      open: (ctx) => showTvOptionDialog<String>(
        context: ctx,
        title: '选择',
        currentValue: 'a',
        onSelected: (v) => selected = v,
        options: options,
      ),
    );
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('opt_b')));
    await tester.pumpAndSettle();
    expect(selected, 'b');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('非 TV：无 RemoteShell，点选行回调并关闭', (tester) async {
    String? selected;
    await pumpHost(
      tester,
      tvMode: false,
      remote: false,
      open: (ctx) => showTvOptionDialog<String>(
        context: ctx,
        title: '选择',
        currentValue: 'b',
        onSelected: (v) => selected = v,
        options: options,
      ),
    );
    await openDialog(tester);

    // 当前值 = b → b 行对勾
    expect(
      find
          .descendant(
            of: find.byKey(const Key('opt_b')),
            matching: find.byType(Icon),
          )
          .evaluate()
          .isNotEmpty,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('opt_c')));
    await tester.pumpAndSettle();
    expect(selected, 'c');
  });

  testWidgets('点遮罩关闭且不触发回调', (tester) async {
    String? selected;
    await pumpHost(
      tester,
      open: (ctx) => showTvOptionDialog<String>(
        context: ctx,
        title: '选择',
        currentValue: 'a',
        onSelected: (v) => selected = v,
        options: options,
      ),
    );
    await openDialog(tester);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(selected, isNull);
  });

  testWidgets('支持可空值选项（每集版本单选 null=默认）', (tester) async {
    String? selected = 'sentinel';
    const epOptions = [
      TvOptionEntry<String?>(value: null, label: '默认', key: Key('ep_default')),
      TvOptionEntry<String?>(value: 's1', label: '版本1', key: Key('ep_s1')),
    ];
    await pumpHost(
      tester,
      open: (ctx) => showTvOptionDialog<String?>(
        context: ctx,
        title: '选择版本',
        currentValue: null,
        onSelected: (v) => selected = v,
        options: epOptions,
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ep_default')), findsOneWidget);
    expect(find.byKey(const Key('ep_s1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ep_s1')));
    await tester.pumpAndSettle();
    expect(selected, 's1');
  });
}

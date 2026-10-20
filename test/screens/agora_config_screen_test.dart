import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  FakeAgoraConfigNotifier? agora,
  AppSettings settings = const AppSettings(),
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      agoraConfigProvider
          .overrideWith((ref) => agora ?? FakeAgoraConfigNotifier()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AgoraConfigScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    finder.evaluate().single,
    alignment: 0.45,
  );
  await tester.pumpAndSettle();
}

Future<void> _openGuideBook(WidgetTester tester) async {
  final cover = find.byKey(const ValueKey('agoraBookCover'));
  await _reveal(tester, cover);
  await tester.tap(cover);
  await tester.pumpAndSettle();
}

Future<void> _openConfigPage(WidgetTester tester) async {
  if (find.byKey(const ValueKey('agoraBookCover')).evaluate().isNotEmpty) {
    await _openGuideBook(tester);
  }
  final dot = find.byKey(const ValueKey('agoraBookDot_4'));
  await _reveal(tester, dot);
  await tester.tap(dot);
  await tester.pumpAndSettle();
}

Future<void> _enterField(
  WidgetTester tester,
  String key,
  String text,
) async {
  final field = find.byKey(ValueKey(key));
  await _reveal(tester, field);
  await tester.enterText(field, text);
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始只显示书本封面，配置表单在第五页', (tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);
    expect(find.text('未配置'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await _openGuideBook(tester);
    expect(find.text('步骤 1 / 5'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await _openConfigPage(tester);
    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('封面点击鹅毛笔直接跳到第五页配置', (tester) async {
    await _pumpScreen(tester);

    final quill = find.byKey(const ValueKey('agoraQuillButton'));
    expect(quill, findsOneWidget);
    await _tapAndSettle(tester, quill);

    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraAppIdField')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraCertField')), findsOneWidget);
  });

  testWidgets('窄屏下点鹅毛笔直达第五页且不溢出', (tester) async {
    await _pumpScreen(tester, size: const Size(320, 640));

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraQuillButton')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraAppIdField')), findsOneWidget);
  });

  testWidgets('未配置时第五页显示填写表单', (tester) async {
    await _pumpScreen(tester);
    await _openConfigPage(tester);

    expect(find.text('填写 App ID 后即可开房与加入房间'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraAppIdField')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraCertField')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraSaveButton')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsNothing);
  });

  testWidgets('窄屏下第五页配置表单不溢出', (tester) async {
    await _pumpScreen(tester, size: const Size(320, 640));
    await _openConfigPage(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('agoraAppIdField')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraCertField')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraSaveButton')), findsOneWidget);
  });

  testWidgets('无扫码入口（声网仅手动配置，非 TV 同样无）', (tester) async {
    await _pumpScreen(tester);

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });

  testWidgets('TV 模式同样无扫码入口', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });

  testWidgets('TV 模式输入框被 ExcludeFocus（防御性，v1.1.177）', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));
    await _openConfigPage(tester);

    expect(find.byType(TextField), findsNWidgets(2));
    for (final field in find.byType(TextField).evaluate()) {
      expect(
        find.ancestor(
          of: find.byWidget(field.widget),
          matching: find.byType(ExcludeFocus),
        ),
        findsOneWidget,
        reason: 'TV 下声网表单输入框必须屏蔽焦点',
      );
    }
  });

  testWidgets('App ID 为空时保存被拒绝', (tester) async {
    final container = await _pumpScreen(tester);
    await _openConfigPage(tester);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraSaveButton')),
    );

    expect(container.read(agoraConfigProvider), isNull);
    expect(find.text('App ID 不能为空'), findsOneWidget);
    await _settleSnackbars(tester);
  });

  testWidgets('填写 App ID 与证书后保存成功', (tester) async {
    final container = await _pumpScreen(tester);
    await _openConfigPage(tester);

    await _enterField(tester, 'agoraAppIdField', 'a' * 32);
    await _enterField(tester, 'agoraCertField', 'certificate');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraSaveButton')),
    );

    final config = container.read(agoraConfigProvider);
    expect(config, isNotNull);
    expect(config!.isConfigured, isTrue);
    expect(config.appId, 'a' * 32);
    expect(find.text('已配置'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await _settleSnackbars(tester);
  });

  testWidgets('清空后回到未配置状态', (tester) async {
    final agora = FakeAgoraConfigNotifier();
    await _pumpScreen(tester, agora: agora);
    await _openConfigPage(tester);

    await _enterField(tester, 'agoraAppIdField', 'a' * 32);
    await _enterField(tester, 'agoraCertField', 'certificate');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraSaveButton')),
    );
    await _settleSnackbars(tester);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraClearButton')),
    );

    expect(find.text('未配置'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraAppIdField')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsNothing);
    await _settleSnackbars(tester);
  });

  testWidgets('页面内嵌声网指南书，首次显示做旧封面', (tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const ValueKey('agoraGuideBook')), findsOneWidget);
    expect(find.text('声网接入指南'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);
    expect(find.text('步骤 1 / 5'), findsNothing);
    expect(find.text('共 5 步 · 左右滑动阅读'), findsOneWidget);
    expect(find.text('配置说明'), findsNothing);
    expect(find.byTooltip('配置说明'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('指南书封面跟随设置主题色', (tester) async {
    const accent = Color(0xFFEC4899);
    await _pumpScreen(
      tester,
      settings: const AppSettings(themeColor: 0xFFEC4899),
    );

    final container = tester.widget<Container>(
      find.byKey(const ValueKey('agoraBookCoverSurface')),
    );
    final gradient =
        (container.decoration! as BoxDecoration).gradient! as LinearGradient;

    expect(
      gradient.colors,
      contains(AgoraBookPalette.fromAccent(accent).leather),
    );
  });

  testWidgets('指南书可通过箭头翻页，第五页为配置页', (tester) async {
    await _pumpScreen(tester);
    await _openGuideBook(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('agoraBookNext')));
    await tester.pumpAndSettle();

    var prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookPrev')),
    );
    expect(prev.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('agoraBookNext')));
    await tester.pumpAndSettle();

    expect(find.text('步骤 2 / 5'), findsOneWidget);
    expect(find.text('开通体验版套餐包'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_1')), findsOneWidget);
    prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookPrev')),
    );
    expect(prev.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('agoraBookPrev')));
    await tester.pumpAndSettle();
    expect(find.text('步骤 1 / 5'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('agoraBookNext')));
      await tester.pumpAndSettle();
    }
    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_4')), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookNext')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('指南书内点击截图可放大，并可用「关闭」退出', (tester) async {
    await _pumpScreen(tester);
    await _openGuideBook(tester);

    // 3.47 起测试环境 asset decode 为真实异步，pumpAndSettle 等不到 →
    // runAsync 预缓存步骤图，否则 Image 宽为 0，tap 必 miss。
    final ctx = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/agora_step1.png'), ctx));
    await tester.pumpAndSettle();

    final image = find.byKey(const ValueKey('agoraBookImage_0'));
    await tester.ensureVisible(image);
    await tester.pumpAndSettle();
    await tester.tap(image);
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsNothing);
    expect(find.byKey(const ValueKey('agoraBookPage_0')), findsOneWidget);
  });

  testWidgets('已配置时第五页默认收起表单，点编辑展开', (tester) async {
    await _pumpScreen(
      tester,
      agora: FakeAgoraConfigNotifier(
        AgoraConfigModel(appId: 'a' * 32, appCertificate: 'certificate'),
      ),
    );
    await _openConfigPage(tester);

    expect(find.text('已配置'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.byKey(const ValueKey('agoraEditButton')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空'), findsOneWidget);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraEditButton')),
    );

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('保存'), findsOneWidget);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraCancelEdit')),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('已配置'), findsOneWidget);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraEditButton')),
    );
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, 'a' * 32);
    expect(fields[1].controller!.text, 'certificate');
  });

  testWidgets('编辑后保存成功自动收起表单', (tester) async {
    final agora = FakeAgoraConfigNotifier(
      AgoraConfigModel(appId: 'a' * 32, appCertificate: 'old_cert'),
    );
    await _pumpScreen(tester, agora: agora);
    await _openConfigPage(tester);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraEditButton')),
    );
    await _enterField(tester, 'agoraCertField', 'new_cert');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraSaveButton')),
    );

    expect(agora.state?.appCertificate, 'new_cert');
    expect(find.byType(TextField), findsNothing);
    await _settleSnackbars(tester);
  });

  testWidgets('切走分支（epoch bump）→ 书本合上、未保存输入还原', (tester) async {
    final agora = FakeAgoraConfigNotifier(
      AgoraConfigModel(appId: 'a' * 32, appCertificate: 'old_cert'),
    );
    final container = await _pumpScreen(tester, agora: agora);
    await _openConfigPage(tester);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraEditButton')),
    );
    await _enterField(tester, 'agoraAppIdField', 'UNSAVED' * 4);
    await _enterField(tester, 'agoraCertField', 'UNSAVED_CERT');

    container.read(shellBranchEpochProvider.notifier).bump(3);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);
    expect(find.text('配置 / 5'), findsNothing, reason: '书本应回到合上封面');
    expect(find.byType(TextField), findsNothing, reason: '表单应收起');
    expect(agora.state?.appId, 'a' * 32, reason: '未保存修改应丢弃');

    await _openConfigPage(tester);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('agoraEditButton')),
    );
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, 'a' * 32);
    expect(fields[1].controller!.text, 'old_cert');
  });
}

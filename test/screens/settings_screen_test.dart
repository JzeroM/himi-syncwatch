import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
  bool remote = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(initial)),
    ],
  );
  addTearDown(container.dispose);

  const Widget page = MaterialApp(home: SettingsScreen());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // TV 壳与生产（MaterialApp.builder）同款：遥控器按键层 +
      // directional 导航模式（Slider 上下键放行）
      child: remote ? TvRemoteShell(child: page) : page,
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _glassSwitch(WidgetTester tester) {
  return find.descendant(
    of: find.ancestor(
      of: find.text('液态玻璃'),
      matching: find.byType(SwitchListTile),
    ),
    matching: find.byType(Switch),
  );
}

void main() {
  /// 滚到目标文本并回滚一段：滚动停点常把目标顶到视口最上沿
  /// （y≈0，被透明 AppBar 遮挡，tap/drag 必 miss）。
  Future<void> _scrollToText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
  }

  Future<void> _scrollToGlass(WidgetTester tester) =>
      _scrollToText(tester, '液态玻璃');

  testWidgets('设置页展示液态玻璃开关（默认开）', (tester) async {
    final container = await _pumpScreen(tester);
    await _scrollToGlass(tester);

    expect(find.text('液态玻璃'), findsOneWidget);
    expect(
      find.text('毛玻璃模糊与高光效果，低端设备可关闭以提升流畅度'),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).glassUi, isTrue);
    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isTrue);
  });

  testWidgets('切换开关后 glassUi 变为 false', (tester) async {
    final container = await _pumpScreen(tester);
    await _scrollToGlass(tester);

    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isFalse);
  });

  testWidgets('再次切换恢复开启', (tester) async {
    final container =
        await _pumpScreen(tester, initial: const AppSettings(glassUi: false));
    await _scrollToGlass(tester);

    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isFalse);

    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isTrue);
  });

  testWidgets('TV 模式开关默认关，切换后 tvMode 为 true', (tester) async {
    final container = await _pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('TV 模式'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('TV 模式'), findsOneWidget);
    expect(container.read(settingsProvider).tvMode, isFalse);

    final tvSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('TV 模式'),
        matching: find.byType(SwitchListTile),
      ),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(tvSwitch).value, isFalse);

    await tester.tap(tvSwitch);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).tvMode, isTrue);
  });

  testWidgets('显示网速开关默认开，切换写入 settings', (tester) async {
    final container = await _pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('显示网速'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('显示网速'), findsOneWidget);
    expect(container.read(settingsProvider).showNetworkSpeed, isTrue);

    final speedSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('显示网速'),
        matching: find.byType(SwitchListTile),
      ),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(speedSwitch).value, isTrue, reason: '默认开');

    await tester.tap(speedSwitch);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).showNetworkSpeed, isFalse);

    await tester.tap(speedSwitch);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).showNetworkSpeed, isTrue);
  });

  testWidgets('TV 遥控器 OK 两段式：作用域落焦首个交互项并激活', (tester) async {
    final container = await _pumpScreen(
      tester,
      initial: const AppSettings(themeColor: 0xFF86E3D6),
      remote: true,
    );
    expect(container.read(settingsProvider).themeColor, isNotNull);

    // 第一段：焦点停在页面作用域，OK 落焦到首个交互项（主题色默认块）
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
    expect(container.read(settingsProvider).themeColor, isNotNull);

    // 第二段：焦点在默认色块上，OK 激活（清空主题色）
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).themeColor, isNull);
  });

  testWidgets('展示主题色分节（标题+默认块+12色块+预览+三滑块）', (tester) async {
    final container = await _pumpScreen(tester);

    expect(find.text('主题色'), findsOneWidget);
    expect(find.byKey(const ValueKey('themeColorDefault')), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      expect(find.byKey(ValueKey('themeColorBlock_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('themeColorPreview')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeHueSlider')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeSatSlider')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeValSlider')), findsOneWidget);

    // 缺省：默认底色，选中默认块
    expect(container.read(settingsProvider).themeColor, isNull);
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('themeColorPreview')),
    );
    final box = preview.decoration as BoxDecoration;
    final gradient = box.gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    // 默认（accent null）时三段同色 = 应用底色
    expect(gradient.colors.toSet(), hasLength(1));
  });

  testWidgets('点击预设色块写入 themeColor', (tester) async {
    final container = await _pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('themeColorBlock_0')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeColor, equals(0xFF6366F1));

    // 预览变为主题色三段渐变（首段为压暗后的主题色）
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('themeColorPreview')),
    );
    final gradient =
        (preview.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(gradient.colors.toSet().length, 3);
  });

  testWidgets('初始选中色块后点击默认清空 themeColor', (tester) async {
    final container = await _pumpScreen(
      tester,
      initial: const AppSettings(themeColor: 0xFF22D3EE),
    );

    expect(container.read(settingsProvider).themeColor, equals(0xFF22D3EE));

    await tester.tap(find.byKey(const ValueKey('themeColorDefault')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeColor, isNull);
  });

  testWidgets('拖动色相滑块写入主题色', (tester) async {
    final container = await _pumpScreen(tester);

    // 滑块初始已在视口内，直接拖动（ensureVisible 会把它顶到 AppBar 下被遮挡）
    final slider = find.byKey(const ValueKey('themeHueSlider'));
    expect(tester.getCenter(slider).dy, greaterThan(56));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();

    final color = container.read(settingsProvider).themeColor;
    expect(color, isNotNull);
    expect(color, isNot(equals(0xFF6366F1)));
  });

  testWidgets('音频后端默认为自动', (tester) async {
    final container = await _pumpScreen(tester);
    // 分类页列数分节插入前部后，音频后端行已超出初始视口（视口外不 mount）
    await tester.scrollUntilVisible(
      find.text('音频后端'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('音频后端'), findsOneWidget);
    expect(
      find.text('使用系统默认音频后端（默认）'),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).audioRenderer, 'auto');
  });

  testWidgets('Windows 平台隐藏音频后端设置项', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpScreen(tester);

      expect(find.text('音频后端'), findsNothing);
      // 相邻设置项仍正常展示（分隔线未错乱）
      expect(find.text('立体声降混'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('播放调试面板'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('播放调试面板'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS 平台隐藏音频后端设置项（Android 专属后端）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpScreen(tester);

      expect(find.text('音频后端'), findsNothing);
      expect(find.text('立体声降混'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('播放调试面板'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('播放调试面板'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---- TV 遥控器 × 主题色滑块（directional 注入回归） ----

  /// 焦点是否位于 [finder] 所指子树内。
  bool focusWithin(Finder finder) {
    final top = finder.evaluate().firstOrNull;
    if (top == null) return false;
    final node = FocusManager.instance.primaryFocus?.context;
    if (node is! Element) return false;
    var found = false;
    node.visitAncestorElements((a) {
      if (a == top) {
        found = true;
        return false;
      }
      return true;
    });
    return found || node == top;
  }

  Future<void> moveToHueSlider(WidgetTester tester) async {
    // OK 两段式：先落焦首个交互项（主题色默认块）
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final hue = find.byKey(const ValueKey('themeHueSlider'));
    var guard = 0;
    while (!focusWithin(hue) && guard < 30) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      guard++;
    }
    expect(focusWithin(hue), isTrue, reason: '方向键应能走到色相滑块');
  }

  testWidgets('TV：滑块上按↓焦点下移且不改主题色（上下键放行）', (tester) async {
    final container = await _pumpScreen(
      tester,
      remote: true,
      initial: const AppSettings(tvMode: true),
    );
    await moveToHueSlider(tester);
    expect(container.read(settingsProvider).themeColor, isNull,
        reason: '焦点移动不应触发调值');

    // directional 模式：Slider 只消费左右键，↑↓放行给焦点导航
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusWithin(find.byKey(const ValueKey('themeHueSlider'))), isFalse,
        reason: '上/下键不应被滑块吞掉');
    expect(container.read(settingsProvider).themeColor, isNull,
        reason: '上/下键不改变滑块值');

    // 焦点还能继续下移（不卡死在滑块上）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
  });

  testWidgets('TV：滑块上按←→调值（左右键保留滑块交互）', (tester) async {
    final container = await _pumpScreen(
      tester,
      remote: true,
      initial: const AppSettings(tvMode: true),
    );
    await moveToHueSlider(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final color = container.read(settingsProvider).themeColor;
    expect(color, isNotNull, reason: '左右键应调整滑块值写入主题色');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(container.read(settingsProvider).themeColor, isNotNull);
  });

  testWidgets('非 TV：未挂载 TV 遥控壳（不注入 directional）', (tester) async {
    await _pumpScreen(tester);
    expect(find.byType(TvRemoteShell), findsNothing);
  });

  // ---- TV 模式 × 解码方式/音频后端（DropdownButton 遥控不可选 → 弹窗） ----

  testWidgets('非 TV：解码方式仍为 DropdownButton 下拉', (tester) async {
    await _pumpScreen(tester);
    // ListView 按可见区 mount，不数全页下拉总数，只断言解码方式行内
    // 是下拉（触摸交互），而非 TV 弹窗
    expect(find.text('解码方式'), findsOneWidget);
    final decodeDropdown = find.descendant(
      of: find.ancestor(
        of: find.text('解码方式'),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(DropdownButton<String>),
    );
    expect(decodeDropdown, findsOneWidget);
  });

  // ---- 视频输出通道（Android 黑屏多档取证） ----

  testWidgets('Android 展示视频输出设置，默认纹理', (tester) async {
    final container = await _pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('视频输出'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('视频输出'), findsOneWidget);
    expect(
      find.text('Flutter 纹理通道（默认）'),
      findsOneWidget,
      reason: '默认档描述',
    );
    expect(container.read(settingsProvider).videoOutput, 'texture');
  });

  testWidgets('非 TV：视频输出下拉切换写入 surfaceView', (tester) async {
    final container = await _pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('视频输出'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // scrollUntilVisible 末尾自动 ensureVisible 会把行顶到视口顶部，
    // 藏进 AppBar（透明但拦截 hit test）；手动下移让出行再点下拉
    final dd = find.byType(DropdownButton<String>).last;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(dd);
    await tester.pumpAndSettle();

    await tester.tap(find.text('SurfaceView'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).videoOutput, 'surfaceView');
    expect(
      find.text('独立显示层，绕过 Flutter 合成，TV 全分辨率输出（黑屏时尝试）'),
      findsOneWidget,
      reason: '行尾描述随档位更新',
    );
  });

  testWidgets('TV：视频输出行点开底部弹窗，选择纹理+直通写入', (tester) async {
    final container =
        await _pumpScreen(tester, initial: const AppSettings(tvMode: true));
    expect(find.byType(DropdownButton<String>), findsNothing,
        reason: 'TV 模式全部走底部弹窗');

    await tester.scrollUntilVisible(
      find.text('视频输出'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // 同非 TV 用例：行被 ensureVisible 顶到 AppBar 下，下移让出后再点
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();

    await tester.tap(find.text('视频输出'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settingOption_texture')), findsOneWidget);
    expect(find.byKey(const Key('settingOption_tunnel')), findsOneWidget);
    expect(find.byKey(const Key('settingOption_surfaceView')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingOption_tunnel')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).videoOutput, 'tunnel');
    expect(find.byKey(const Key('settingOption_tunnel')), findsNothing,
        reason: '选中后弹窗应关闭');
  });

  testWidgets('Windows 平台隐藏视频输出设置项（Android 专属）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpScreen(tester);

      expect(find.text('视频输出'), findsNothing);
      expect(find.text('渲染兼容模式（实验）'), findsNothing);
      // 近处相邻设置项初始视口内展示
      expect(find.text('解码方式'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('播放调试面板'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('播放调试面板'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android 展示渲染兼容模式开关，默认关闭', (tester) async {
    final container = await _pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('渲染兼容模式（实验）'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('渲染兼容模式（实验）'), findsOneWidget);
    expect(find.textContaining('需重启应用生效'), findsOneWidget);
    expect(container.read(settingsProvider).renderCompatMode, isFalse);
  });

  testWidgets('渲染兼容模式开关切换写入设置', (tester) async {
    final container = await _pumpScreen(tester);
    final row = find.ancestor(
      of: find.text('渲染兼容模式（实验）'),
      matching: find.byType(SwitchListTile),
    );
    await tester.scrollUntilVisible(
      find.text('渲染兼容模式（实验）'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 列表尾部内容变化会使 scrollUntilVisible 停点漂移到 AppBar 下，
    // 物理 tap 可能被遮挡——直接调 onChanged 验证写入链路
    final sw = tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)));
    sw.onChanged!(true);
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).renderCompatMode, isTrue);
  });

  testWidgets('TV：解码方式行点开底部弹窗，选择软解写入', (tester) async {
    final container = await _pumpScreen(
      tester,
      initial: const AppSettings(tvMode: true),
    );
    // 非 TV 的 DropdownButton 不再出现
    expect(find.byType(DropdownButton<String>), findsNothing);

    await tester.tap(find.text('解码方式'));
    await tester.pumpAndSettle();

    // 底部弹窗：RadioListTile 三选项（遥控器经 TvRemoteShortcuts 可选）
    expect(find.byKey(const Key('settingOption_auto')), findsOneWidget);
    expect(find.byKey(const Key('settingOption_hw')), findsOneWidget);
    expect(find.byKey(const Key('settingOption_sw')), findsOneWidget);
    expect(container.read(settingsProvider).decodeMode, 'auto');

    await tester.tap(find.byKey(const Key('settingOption_sw')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).decodeMode, 'sw');
    expect(find.byKey(const Key('settingOption_sw')), findsNothing,
        reason: '选中后弹窗应关闭');
    expect(find.text('软解'), findsWidgets, reason: '行尾显示当前值');
  });

  testWidgets('TV：音频后端行点开底部弹窗，选择 AAudio 写入', (tester) async {
    // 分类页列数分节插入前部后，音频后端行超出 600 默认视口——
    // 加高视口使初始即可见（与焦点描边用例同策略）
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = await _pumpScreen(
      tester,
      initial: const AppSettings(tvMode: true),
    );
    expect(find.text('音频后端'), findsOneWidget);

    await tester.tap(find.text('音频后端'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settingOption_AAudio')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingOption_AAudio')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).audioRenderer, 'AAudio');
    expect(find.byKey(const Key('settingOption_AAudio')), findsNothing);
  });

  // ---- TV 焦点样式统一（"同屏两个焦点框"回归） ----

  testWidgets('TV：设置行移动焦点后同屏仅一个描边，落点为 TvFocusable 包装', (tester) async {
    // 结构性依赖"初始视口内 解码/立体声降混/音频后端 三行可见"（不能滚动，
    // scrollUntilVisible 会把解码行顶出视口破坏落焦）：分类页列数分节插入
    // 前部后三行整体下移，加高视口让三行回到初始视口内
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = await _pumpScreen(
      tester,
      remote: true,
      initial: const AppSettings(tvMode: true),
    );
    // 不滚动：初始视口内 解码方式/立体声降混/音频后端 三行均可见，
    // scrollUntilVisible 会把解码行顶出视口（元素卸载）破坏落焦

    // 所有开关行必须 ExcludeFocus：行内 Switch/InkWell 焦点节点若可聚焦，
    // 内层蓝色 focusColor 会与外层描边同屏双显
    final switchTiles = find.byType(SwitchListTile);
    expect(switchTiles, findsWidgets);
    for (final tile in tester.widgetList<SwitchListTile>(switchTiles)) {
      expect(
        find.ancestor(
            of: find.byWidget(tile), matching: find.byType(ExcludeFocus)),
        findsWidgets,
        reason: 'TV 模式开关行应 ExcludeFocus（防内层蓝底双显）',
      );
    }

    Finder tvWrappers() => find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');

    int outlineCount() => tester
        .widgetList<AnimatedContainer>(find.descendant(
          of: tvWrappers(),
          matching: find.byType(AnimatedContainer),
        ))
        .where((c) => c.foregroundDecoration != null)
        .length;

    // 直接落焦解码方式行（跳过主题色区裸 InkWell/滑块）：
    // 包装 Focus 是文本的祖先（Focus > ... > ListTile > Text）
    final decodeWrapper = find.ancestor(
      of: find.text('解码方式'),
      matching: tvWrappers(),
    );
    final decodeNode = tester.widget<Focus>(decodeWrapper).focusNode!;
    decodeNode.requestFocus();
    await tester.pumpAndSettle();
    expect(outlineCount(), 1, reason: '落焦后仅该行有描边');

    // ↓ 移到立体声降混（原裸 SwitchListTile）：落点应为外层包装而非行内蓝底
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final stereoNode = FocusManager.instance.primaryFocus;
    expect(stereoNode?.debugLabel, 'TvFocusable',
        reason: '焦点应落在 TvFocusable 包装上（而非 SwitchListTile 内层）');
    expect(stereoNode, isNot(decodeNode), reason: '焦点确实移动了');
    expect(outlineCount(), 1, reason: '同屏仅一个焦点描边目标（失焦行零时长瞬时移除）');
    // 动画时长语义：失焦行 duration 必须为 0，聚焦行 120ms。
    // 加高视口后可见行数不定（不再硬编码 3 行），按语义断言：
    // 恰好一个聚焦行、其余全部失焦瞬时移除
    final durations = tester
        .widgetList<AnimatedContainer>(find.descendant(
          of: tvWrappers(),
          matching: find.byType(AnimatedContainer),
        ))
        .map((c) => c.duration)
        .toList();
    expect(
      durations.where((d) => d == const Duration(milliseconds: 120)).length,
      1,
      reason: '解码/立体声/音频后端…全部可见行中仅立体声行聚焦淡入（120ms）',
    );
    expect(
      durations.where((d) => d != Duration.zero).length,
      1,
      reason: '其余行全部失焦 0ms 瞬时移除（防双焦点框）',
    );

    // OK 键经外层 onTap 切换开关
    final initial = container.read(settingsProvider).stereoDownmix;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).stereoDownmix, isNot(initial),
        reason: 'TV OK 键应切换开关');

    // 继续 ↓ 到下一行（音频后端，Android 专属），同样保持唯一描边
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final nextNode = FocusManager.instance.primaryFocus;
    expect(nextNode?.debugLabel, 'TvFocusable');
    expect(nextNode, isNot(stereoNode), reason: '焦点继续下移');
    expect(outlineCount(), 1);
  });

  testWidgets('分类页每行海报数滑块：默认自动，改值落盘，0 回自动', (tester) async {
    final container = await _pumpScreen(tester);

    // 分节在列表尾部：SliverList extent 滚动中动态增长，scrollUntilVisible
    // 可能停在元素将被回收的位置——用 dragUntilVisible 兜底滚到可见
    final sliderFinder = find.byKey(const ValueKey('categoryColumnsSlider'));
    if (sliderFinder.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        sliderFinder,
        find.byType(Scrollable).first,
        const Offset(0, -250),
      );
    }
    await tester.pumpAndSettle();
    expect(sliderFinder.evaluate(), isNotEmpty, reason: '滑块应挂载到元素树');

    expect(
      find.byKey(const ValueKey('categoryColumnsSlider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('categoryColumnsValue')),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).categoryColumns, isNull,
        reason: '默认自动');

    // key 直接挂在 Text 上：byKey 即文本 finder（descendant 不含自身）
    final valueText = find.byKey(const ValueKey('categoryColumnsValue'));
    expect(tester.widget<Text>(valueText).data, '自动');

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('categoryColumnsSlider')),
    );
    expect(slider.value, 0, reason: '自动对应滑块 0 档');
    expect(slider.max, 14);
    expect(slider.divisions, 14);

    // 拖到 8 → 落盘指定值，文案更新
    slider.onChanged!(8);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).categoryColumns, 8);
    expect(tester.widget<Text>(valueText).data, '每行 8 个');

    // 回 0 → 清回自动（null），不落键
    slider.onChanged!(0);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).categoryColumns, isNull);
    expect(tester.widget<Text>(valueText).data, '自动');
    expect(
      container.read(settingsProvider).toJson().containsKey('categoryColumns'),
      isFalse,
    );
  });
  group('玻璃参数滑杆分组（v1.1.84）', () {
    testWidgets('Android：展示标题、6 个滑杆与恢复默认（默认态禁用）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final container = await _pumpScreen(tester);
        await _scrollToText(tester, '玻璃参数');

        expect(find.text('玻璃参数'), findsOneWidget);
        expect(find.text('实时调节磨砂与折射效果，拖动即生效'), findsOneWidget);
        for (final key in const [
          'glassBlur',
          'glassThickness',
          'glassEdgeZone',
          'glassSaturation',
          'glassChromatic',
          'glassLightIntensity',
        ]) {
          expect(find.byKey(ValueKey('${key}Slider')), findsOneWidget,
              reason: '$key 滑杆缺失');
        }
        expect(find.text('折射范围'), findsOneWidget, reason: '折射范围滑杆标签');
        // 默认态（全包默认）：恢复默认按钮禁用
        final reset = tester.widget<TextButton>(
            find.byKey(const ValueKey('glassResetDefaults')));
        expect(reset.onPressed, isNull);
        expect(container.read(settingsProvider).glassBlur, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('拖动磨砂滑杆写入 glassBlur 并落盘', (tester) async {
      final container = await _pumpScreen(tester);
      await _scrollToText(tester, '玻璃参数');

      final persistBefore =
          (container.read(settingsProvider.notifier) as FakeSettingsNotifier)
              .persistCount;
      final slider = find.byKey(const ValueKey('glassBlurSlider'));
      await tester.drag(slider, const Offset(60, 0));
      await tester.pumpAndSettle();

      final v = container.read(settingsProvider).glassBlur;
      expect(v, isNotNull, reason: '拖动后写入');
      expect(v, greaterThan(4), reason: '向右拖增大（应用默认 4）');
      final notifier =
          container.read(settingsProvider.notifier) as FakeSettingsNotifier;
      expect(notifier.persistCount, greaterThan(persistBefore),
          reason: 'update 触发落盘');
      // 回显文本更新 + 恢复默认按钮可用
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('glassValue_glassBlur')))
            .data,
        isNot(equals('4.0')),
      );
      expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('glassResetDefaults')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('拖动玻璃滑杆不抹掉其余已设参数（v1.1.85 回归：清空 bug）', (tester) async {
      final container = await _pumpScreen(
        tester,
        initial: const AppSettings(
          glassThickness: 40,
          glassEdgeZone: 22,
          glassSaturation: 2.2,
          glassChromatic: 0.3,
          glassLightIntensity: 1.6,
        ),
      );
      await _scrollToText(tester, '玻璃参数');

      final slider = find.byKey(const ValueKey('glassBlurSlider'));
      await tester.drag(slider, const Offset(60, 0));
      await tester.pumpAndSettle();

      final s = container.read(settingsProvider);
      expect(s.glassBlur, isNotNull, reason: '拖动字段写入');
      expect(s.glassThickness, 40, reason: '其余字段不能被清空');
      expect(s.glassEdgeZone, 22, reason: '折射范围不能被清空');
      expect(s.glassSaturation, 2.2);
      expect(s.glassChromatic, 0.3);
      expect(s.glassLightIntensity, 1.6);
    });

    testWidgets('Android：拖动折射范围滑杆写入 glassEdgeZone（20~24 整数档）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final container = await _pumpScreen(tester);
        await _scrollToText(tester, '玻璃参数');

        final slider = find.byKey(const ValueKey('glassEdgeZoneSlider'));
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();

        final v = container.read(settingsProvider).glassEdgeZone;
        expect(v, isNotNull, reason: '拖动后写入');
        expect(v, inInclusiveRange(20, 24), reason: '值域 20~24');
        expect(v, greaterThan(20), reason: '向右拖增档（默认 20）');
        expect(v, equals(v!.roundToDouble()), reason: '整数四档');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS 隐藏折射范围滑杆（premium 路径无效），其余 5 个保留', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pumpScreen(tester);
        await _scrollToText(tester, '玻璃参数');

        expect(find.text('玻璃参数'), findsOneWidget);
        expect(find.byKey(const ValueKey('glassEdgeZoneSlider')), findsNothing,
            reason: 'iOS premium 路径不读 uEdgeZone，滑杆无效须隐藏');
        expect(find.text('折射范围'), findsNothing);
        for (final key in const [
          'glassBlur',
          'glassThickness',
          'glassSaturation',
          'glassChromatic',
          'glassLightIntensity',
        ]) {
          expect(find.byKey(ValueKey('${key}Slider')), findsOneWidget,
              reason: '$key 滑杆在 iOS 保留');
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('TV 模式隐藏折射范围滑杆，其余 5 个保留', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpScreen(
          tester,
          initial: const AppSettings(tvMode: true),
        );
        await _scrollToText(tester, '玻璃参数');

        expect(find.text('玻璃参数'), findsOneWidget);
        expect(find.byKey(const ValueKey('glassEdgeZoneSlider')), findsNothing,
            reason: 'TV 模式滑杆吞方向键，须隐藏');
        expect(find.text('折射范围'), findsNothing);
        expect(find.byKey(const ValueKey('glassBlurSlider')), findsOneWidget,
            reason: '其余滑杆在 TV 模式保留');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('恢复默认清空全部 6 参数并禁用按钮', (tester) async {
      final container = await _pumpScreen(
        tester,
        initial: const AppSettings(
          glassBlur: 9,
          glassThickness: 40,
          glassEdgeZone: 23,
          glassSaturation: 2.2,
          glassChromatic: 0.06,
          glassLightIntensity: 0.9,
        ),
      );
      await _scrollToText(tester, '玻璃参数');

      final reset = find.byKey(const ValueKey('glassResetDefaults'));
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull,
          reason: '非默认态可用');

      await tester.tap(reset);
      await tester.pumpAndSettle();

      final s = container.read(settingsProvider);
      expect(s.glassBlur, isNull);
      expect(s.glassThickness, isNull);
      expect(s.glassEdgeZone, isNull);
      expect(s.glassSaturation, isNull);
      expect(s.glassChromatic, isNull);
      expect(s.glassLightIntensity, isNull);
      expect(tester.widget<TextButton>(reset).onPressed, isNull,
          reason: '已回默认 → 禁用');
    });
  });
}

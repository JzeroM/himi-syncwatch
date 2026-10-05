import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

Future<void> _pumpNav(
  WidgetTester tester, {
  int initial = 0,
  AppSettings settings = const AppSettings(),
  required ValueChanged<int> onSelect,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 800,
              child: ShellNavBar(currentIndex: initial, onSelect: onSelect),
            ),
          ),
        ),
      ),
    ),
  );
}

const ValueKey<String> _navBlob = ValueKey('navBlob');

/// navBlob 键当前挂载的 widget（不存在时为 null）。
Widget? _keyedWidget(WidgetTester tester) {
  final elements = find.byKey(_navBlob).evaluate();
  return elements.isEmpty ? null : elements.first.widget;
}

/// 玻璃开启时 navBlob 键挂在 AnimatedGlassIndicator 上；关闭时是 DecoratedBox。
lg.AnimatedGlassIndicator? _indicatorOrNull(WidgetTester tester) {
  final w = _keyedWidget(tester);
  return w is lg.AnimatedGlassIndicator ? w : null;
}

/// 水珠几何（left/width 随玻璃开关取自 indicator 参数或外层 Positioned）。
({double? left, double? width, double? height}) _blob(WidgetTester tester) {
  final ind = _indicatorOrNull(tester);
  if (ind != null) {
    return (left: ind.exactOffset, width: ind.exactWidth, height: null);
  }
  final pos = tester.widget<Positioned>(
    find.ancestor(of: find.byKey(_navBlob), matching: find.byType(Positioned)),
  );
  return (left: pos.left, width: pos.width, height: pos.height);
}

BoxDecoration _blobDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(_navBlob),
  );
  return box.decoration as BoxDecoration;
}

void main() {
  testWidgets('四格 icon+label 组在 60 高度内严格对齐且整体垂直居中', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final navBox = tester.renderObject<RenderBox>(find.byType(ShellNavBar));
    expect(navBox.size.height, 60);
    final navTop = navBox.localToGlobal(Offset.zero).dy;

    double centerY(Finder f) {
      final box = tester.renderObject<RenderBox>(f);
      final c =
          box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
      return c.dy - navTop;
    }

    // 四格 icon 中线一致（修复 NavigationBar 选中/未选中错位问题）
    final iconCenters = [
      centerY(find.byIcon(Icons.home)),
      centerY(find.byIcon(Icons.dns_outlined)),
      centerY(find.byIcon(Icons.key_outlined)),
      centerY(find.byIcon(Icons.settings_outlined)),
    ];
    expect(iconCenters.toSet().length, 1);

    // 四格 label 中线一致
    final labelCenters = [
      centerY(find.text('首页')),
      centerY(find.text('Emby服务器')),
      centerY(find.text('声网配置')),
      centerY(find.text('设置')),
    ];
    expect(labelCenters.toSet().length, 1);

    // icon+label 组块整体垂直居中于 60 高
    final iconTop = tester
            .renderObject<RenderBox>(find.byIcon(Icons.home))
            .localToGlobal(Offset.zero)
            .dy -
        navTop;
    final labelBox = tester.renderObject<RenderBox>(find.text('首页'));
    final labelBottom =
        labelBox.localToGlobal(Offset.zero).dy + labelBox.size.height - navTop;
    expect((iconTop + labelBottom) / 2, closeTo(30, 1.0));
  });

  testWidgets('初始水珠位于首格中心', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final pos = _blob(tester);
    expect(pos.left, closeTo(0, 0.01));
    expect(pos.width, closeTo(200, 0.01));
  });

  testWidgets('点击切换标签，水珠平滑移到目标格中心', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(selected, 3);
    final pos = _blob(tester);
    expect(pos.left, closeTo(600, 0.5));
    expect(pos.width, closeTo(200, 0.5));
  });

  testWidgets('长按拖动水珠跟手并拉伸，松手落点才切换', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 长按第一格进入拖动
    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(selected, isNull); // 长按本身不切换

    // 拖到第二格：水珠中心跟手、宽度拉伸
    await gesture.moveTo(Offset(nav.left + 300, nav.center.dy));
    await tester.pump();

    final dragging = _blob(tester);
    expect(dragging.left, closeTo(300 - dragging.width! / 2, 1));
    expect(dragging.width, greaterThan(200));
    expect(selected, isNull); // 拖动中途不切换（松手落点才切）

    // 拖到第三格中部松手 → 落点切换
    await gesture.moveTo(Offset(nav.left + 490, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 2);

    // 水珠回弹到第三格中心（left = 0.625*800 - 200/2 = 400）并收窄
    final settled = _blob(tester);
    expect(settled.left, closeTo(400, 0.5));
    expect(settled.width, closeTo(200, 0.5));
  });

  testWidgets('长按拖动后松手在原格，不切换', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(nav.left + 140, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, isNull);
    final settled = _blob(tester);
    expect(settled.left, closeTo(0, 0.5));
    expect(settled.width, closeTo(200, 0.5));
  });

  testWidgets('玻璃开启：navBlob 是镜片指示器而非白色装饰，青色仅用于选中图标', (
    tester,
  ) async {
    await _pumpNav(tester, onSelect: (_) {});

    expect(_indicatorOrNull(tester), isNotNull,
        reason: '玻璃开启时水珠由 AnimatedGlassIndicator 真折射镜片渲染');
    expect(_keyedWidget(tester), isNot(isA<DecoratedBox>()),
        reason: '白色装饰不再叠在镜片上（否则压制折射观感）');

    // 青色只出现在选中图标/文字，不给水珠
    expect(tester.widget<Icon>(find.byIcon(Icons.home)).color, kNavBlobColor);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.dns_outlined)).color,
      Colors.white70,
    );
  });

  testWidgets('水珠饱满：高 50、固定 25 圆角（两端半圆直边）', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final ind = _indicatorOrNull(tester);
    if (ind != null) {
      // 玻璃开启：高度由 indicator 垂直 padding 决定（60 - 2×5 = 50）
      expect(ind.padding, const EdgeInsets.symmetric(vertical: 5));
      expect(ind.borderRadius, 25);
      final inner = find.descendant(
        of: find.byKey(_navBlob),
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && w.left != null && w.width != null,
        ),
      );
      expect(inner, findsOneWidget);
      expect(tester.renderObject<RenderBox>(inner).size.height, 50);
    } else {
      expect(_blob(tester).height, 50);
      expect(
        _blobDecoration(tester).borderRadius,
        BorderRadius.all(Radius.circular(25)),
      );
    }
  });

  testWidgets('glassUi 开启：水珠为 premium 真折射指示器（非包装饰）', (
    tester,
  ) async {
    await _pumpNav(tester, onSelect: (_) {});

    final ind = tester.widget<lg.AnimatedGlassIndicator>(find.byKey(_navBlob));
    expect(ind.quality, lg.GlassQuality.premium,
        reason: '不再恒 standard（根因：standard 走 lightweight 无折射）');
    expect(ind.thickness, 1.0, reason: '静止即镜片（参考图观感）');
    expect(ind.expansion, EdgeInsets.zero,
        reason: '禁用默认 all(8) 外扩，宽度由 exactWidth 驱动');
    expect(ind.padding, const EdgeInsets.symmetric(vertical: 5),
        reason: '60 高导航内水珠 50 高');
    expect(ind.borderRadius, 25);
    expect(ind.paintBackground, isFalse);
    expect(ind.exactOffset, closeTo(0, 0.01));
    expect(ind.exactWidth, closeTo(200, 0.01));
    expect(ind.velocity, isA<double>());
    expect(ind.settings?.chromaticAberration, 0.15,
        reason: '彩虹色散取应用默认（对齐图中彩虹圈）');
    expect(ind.settings?.glassColor, Colors.white.withValues(alpha: 0.10),
        reason: '白色镜片底色恢复图标对比度');

    // 就近遮蔽胶囊的 avoidsRefraction，否则 GlassEffect 走 vibrancy 无折射
    final inherited = tester.widget<lg.InheritedLiquidGlass>(
      find.ancestor(
        of: find.byKey(_navBlob),
        matching: find.byType(lg.InheritedLiquidGlass),
      ),
    );
    expect(inherited.avoidsRefraction, isFalse);
    expect(inherited.quality, lg.GlassQuality.premium);

    // 不再用 GlassContainer 包装饰
    expect(find.byType(lg.GlassContainer), findsNothing);
  });

  testWidgets('glassUi 关闭：水珠降级为纯装饰，无包玻璃', (tester) async {
    await _pumpNav(
      tester,
      settings: const AppSettings(glassUi: false),
      onSelect: (_) {},
    );

    expect(_indicatorOrNull(tester), isNull);
    expect(find.byType(lg.GlassContainer), findsNothing);
    // 原装饰不变
    expect(_blobDecoration(tester).color, Colors.white.withValues(alpha: 0.10));
    expect(_blob(tester).height, 50);
  });

  testWidgets('短时横向滑动即可拖动水珠（无需长按），跟手且松手落点切换', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 按下后立即横滑（远小于长按 500ms 阈值）→ 直接进入拖动
    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump();
    await gesture.moveTo(Offset(nav.left + 300, nav.center.dy));
    await tester.pump();

    final dragging = _blob(tester);
    expect(dragging.left, closeTo(300 - dragging.width! / 2, 1));
    expect(dragging.width, greaterThan(200));
    expect(selected, isNull); // 拖动中途不回调

    // 水珠中心已在第二格 → 该格图标实时点亮青色实心
    expect(find.byIcon(Icons.dns), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.dns)).color, kNavBlobColor);

    // 拖到第三格中部松手 → 落点切换
    await gesture.moveTo(Offset(nav.left + 490, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 2);
    expect(tester.widget<Icon>(find.byIcon(Icons.key)).color, kNavBlobColor);
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
  });

  testWidgets('手指落在非水珠格横向滑动，水珠吸附到手指跟手', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 初始水珠在第一格，直接从第三格按下横滑 → 水珠吸附到手指
    final gesture = await tester.startGesture(
      Offset(nav.left + 500, nav.center.dy),
    );
    await tester.pump();
    await gesture.moveTo(Offset(nav.left + 520, nav.center.dy));
    await tester.pump();

    final dragging = _blob(tester);
    expect(dragging.left, closeTo(520 - dragging.width! / 2, 1));
    expect(selected, isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 2); // 落点在第三格
  });
}

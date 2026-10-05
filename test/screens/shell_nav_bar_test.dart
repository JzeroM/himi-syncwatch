import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/blob_lens.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

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

/// 玻璃开启时 navBlob 键挂在 LiquidBlobLens 上；关闭时是 DecoratedBox。
LiquidBlobLens? _lensOrNull(WidgetTester tester) {
  final w = _keyedWidget(tester);
  return w is LiquidBlobLens ? w : null;
}

/// 水珠几何（left/width 随玻璃开关取自镜片参数或外层 Positioned）。
({double? left, double? width, double? height}) _blob(WidgetTester tester) {
  final lens = _lensOrNull(tester);
  if (lens != null) {
    return (left: lens.left, width: lens.width, height: null);
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

/// 静止实心底胶囊（ShapeDecoration 白 0.10 + 外光晕，无边框）。
Finder _restBackground(WidgetTester tester) {
  return find.descendant(
    of: find.byKey(_navBlob),
    matching: find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is ShapeDecoration &&
          (w.decoration as ShapeDecoration).color ==
              Colors.white.withValues(alpha: 0.10),
    ),
  );
}

/// 活动态外扩矩形（rect top = -11 → 50+22=72，上下各超出胶囊 6px）。
Finder _expandedRect(WidgetTester tester) {
  return find.descendant(
    of: find.byKey(_navBlob),
    matching: find.byWidgetPredicate(
      (w) => w is Positioned && w.top != null && w.top! <= -6.0,
    ),
  );
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

  testWidgets('初始水珠位于首格中心（静止宽 = 格宽 × 0.75 圆润比例）', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final pos = _blob(tester);
    expect(pos.width, closeTo(150, 0.01), reason: '800/4 格宽 200 × 0.75');
    expect(pos.left, closeTo(100 - 150 / 2, 0.01), reason: '首格中心 100 居中');
  });

  testWidgets('点击切换标签，水珠平滑移到目标格中心', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(selected, 3);
    final pos = _blob(tester);
    expect(pos.width, closeTo(150, 0.5));
    expect(pos.left, closeTo(700 - 150 / 2, 0.5), reason: '第四格中心 700');
  });

  testWidgets('长按拖动水珠跟手并整体放大（宽高同比 ×1.44 不拉长），松手落点才切换', (
    tester,
  ) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 长按第一格进入拖动
    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(selected, isNull); // 长按本身不切换

    // 拖到第二格：水珠中心跟手，等弹簧把整体放大拉满
    await gesture.moveTo(Offset(nav.left + 300, nav.center.dy));
    await tester.pump();
    // 按住期间捕获 ticker 每帧活跃 → pumpAndSettle 会死等，改有界推进
    await tester.pump(const Duration(milliseconds: 450));

    final dragging = _blob(tester);
    expect(dragging.left, closeTo(300 - dragging.width! / 2, 1),
        reason: '中心始终对准手指');
    expect(dragging.width, closeTo(150 * 1.44, 0.5),
        reason: '静止 150 整体放大到 ×1.44 = 216（而非拉长）');
    expect(selected, isNull); // 拖动中途不切换（松手落点才切）

    // 拖到第三格中部松手 → 落点切换
    await gesture.moveTo(Offset(nav.left + 490, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 2);

    // 水珠回弹到第三格中心（center = 0.625*800 = 500）并回落静止宽
    final settled = _blob(tester);
    expect(settled.left, closeTo(500 - 150 / 2, 0.5));
    expect(settled.width, closeTo(150, 0.5));
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
    expect(settled.left, closeTo(25, 0.5));
    expect(settled.width, closeTo(150, 0.5));
  });

  testWidgets('玻璃开启：navBlob 是镜片而非白色装饰，青色仅用于选中图标', (
    tester,
  ) async {
    await _pumpNav(tester, onSelect: (_) {});

    expect(_lensOrNull(tester), isNotNull,
        reason: '玻璃开启时水珠由 LiquidBlobLens 真折射镜片渲染');
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

    final lens = _lensOrNull(tester);
    if (lens != null) {
      // 玻璃开启：高度由镜片垂直留白决定（60 - 2×5 = 50）
      expect(lens.paddingV, 5);
      expect(lens.borderRadius, 25);
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

  testWidgets('glassUi 开启：navBlob 是自研 LiquidBlobLens，胶囊作兄弟层不裁剪水珠', (
    tester,
  ) async {
    await _pumpNav(tester, onSelect: (_) {});

    final lens = tester.widget<LiquidBlobLens>(find.byKey(_navBlob));
    expect(lens.activity, 0.0, reason: '静止活动量 0：扁平实心底、镜片不挂载（折射只在移动出现）');
    expect(lens.expansionV, 11, reason: '活动态外扩 11 → 上下各超出胶囊(60) 6px');
    expect(lens.paddingV, 5, reason: '60 高导航内水珠 50 高');
    expect(lens.borderRadius, 25);
    expect(lens.left, closeTo(25, 0.01), reason: '首格中心 100 - 150/2');
    expect(lens.width, closeTo(150, 0.01), reason: '静止宽 = 格宽 200 × 0.75');
    expect(lens.velocity, isA<double>());
    expect(lens.pillShadows.first.blurRadius, 14, reason: '静止外光晕替代旧边框');
    // Skia 捕获钥匙：GlassEffect 捕获门槛 interactionIntensity>0.01
    // && scopeKey≠null && blur>0 —— 无 blur 则背景捕获永不启动，
    // 折射与彩虹色散全部失效（v1.1.87 根因）
    expect(lens.settings.blur, 0.01, reason: '捕获钥匙，0.01 模糊不可感知');
    expect(lens.settings.chromaticAberration, 0.5, reason: '色散固定加强（忽略滑杆）');
    expect(lens.settings.thickness, 28, reason: '镜片深度跟随玻璃厚度滑杆（应用默认 28）');
    expect(lens.settings.glassColor, Colors.white.withValues(alpha: 0.14),
        reason: '白色镜片底色略提亮，配合结构参数增强折射观感');
    // 结构参数（补偿包内标准路径归一化）：ambientRim 驱动中性白微光；
    // glow/ambient 收低弱化白色边框感；edgeAbsorption 收低淡化边缘暗带
    expect(lens.settings.ambientRim, 0.18,
        reason: '中性白微边驱动（×0.7 归一化后 0.126，非硬边框）');
    expect(lens.settings.glowIntensity, 1.2, reason: '白色菲涅尔光晕收敛，弱化边框感');
    expect(lens.settings.ambientStrength, 0.4, reason: '内壁白光提亮收敛');
    expect(lens.settings.edgeAbsorption, 0.10, reason: '边缘暗带淡化，非硬边框');
    expect(LiquidBlobLens.quality, lg.GlassQuality.standard,
        reason:
            '测试环境 isShaderFilterSupported=false → standard（真机 Impeller → premium）');

    // 静止镜片不挂载（折射/物理色散只在移动出现）
    expect(find.byType(GlassEffect), findsNothing);

    // 光源相位随水珠位置：首格 t=0.125 → π/2 + (0.125-0.5)π
    expect(
      lens.settings.lightAngle,
      closeTo(math.pi / 2 + (0.125 - 0.5) * math.pi, 1e-9),
      reason: 'lightAngle 随水珠位置扫动（key/kick 亮瓣随移动流动的驱动）',
    );

    // 镜片就近提供 avoidsRefraction: false，GlassEffect 走真折射而非 vibrancy
    final inherited = tester.widget<lg.InheritedLiquidGlass>(
      find.descendant(
        of: find.byKey(_navBlob),
        matching: find.byType(lg.InheritedLiquidGlass),
      ),
    );
    expect(inherited.avoidsRefraction, isFalse);
    expect(inherited.quality, lg.GlassQuality.standard);

    // 胶囊玻璃底移入导航作为第一层兄弟；水珠不在其裁剪子树内
    expect(find.byType(GlassContainer), findsOneWidget, reason: '胶囊外壳由导航自己绘制');
    expect(find.byType(lg.GlassContainer), findsOneWidget,
        reason: '胶囊真折射玻璃底在导航内');
    expect(
      tester.getSize(find.byType(lg.GlassContainer)),
      const Size(800, 60),
      reason: '胶囊铺满导航',
    );
    expect(
      find.ancestor(
        of: find.byKey(_navBlob),
        matching: find.byType(lg.GlassContainer),
      ),
      findsNothing,
      reason: '水珠与胶囊是兄弟层，包内对子级的无条件裁剪吃不到水珠',
    );
  });

  testWidgets('静止实心无边框，拖动中镜片挂载并外扩超出胶囊 6px，松手回落恢复', (
    tester,
  ) async {
    await _pumpNav(tester, onSelect: (_) {});
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 静止：实心底胶囊（无明显边框）、镜片不挂载、无外扩矩形
    expect(_restBackground(tester), findsOneWidget);
    expect(_expandedRect(tester), findsNothing);
    expect(find.byType(GlassEffect), findsNothing);

    // 长按进入拖动态，等弹簧把活动量拉到 1（按住中捕获 ticker 活跃，
    // 不能 pumpAndSettle，用有界帧推进）
    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 450));

    final moving = tester.widget<LiquidBlobLens>(find.byKey(_navBlob));
    expect(moving.activity, closeTo(1.0, 0.02),
        reason: '拖动中弹簧拉满（有界帧推进，允许微量过冲）');
    expect(_restBackground(tester), findsNothing,
        reason: '活动量 >0.15 后实心底卸载，交棒玻璃镜片');
    expect(_expandedRect(tester), findsOneWidget,
        reason: '活动态矩形外扩 top=-11，水滴整体放大上下各超出胶囊 6px');

    // 整体放大：宽 150→216、高 50→72 同为 ×1.44，比例不变不拉长不压扁
    expect(moving.width, closeTo(150 * 1.44, 0.5), reason: '宽同倍放大到 216');
    final activeRect = tester.renderObject<RenderBox>(_expandedRect(tester));
    expect(activeRect.size.height, closeTo(50 * 1.44, 0.5),
        reason: '高 50→72 同倍放大');
    expect(
      (activeRect.size.width / 150) / (activeRect.size.height / 50),
      closeTo(1.0, 0.01),
      reason: '宽高放大倍数一致 → 纯整体放大，不变形',
    );

    // 镜片挂载且捕获参数就位（折射/真色散只在移动过程出现）
    final effect = tester.widget<GlassEffect>(find.byType(GlassEffect));
    expect(effect.interactionIntensity, closeTo(1.0, 0.02),
        reason: '镜片活动强度随弹簧拉满（允许微量过冲）');
    expect(effect.backgroundKey, isNotNull,
        reason: '采样导航边界（胶囊+图标），非默认 body 边界');
    expect(effect.settings.blur, 0.01, reason: '拷贝态保留 blur 原值供捕获门槛判定');
    expect(effect.settings.chromaticAberration, 0.5,
        reason: '色散输入 0.5，配合 vendored shader ×4.0 出 ~2px 物理彩边');
    expect(effect.settings.visibility, closeTo(1.0, 0.02),
        reason: 'visibility=activity 已淡入完成（允许微量过冲）');
    expect(effect.quality, lg.GlassQuality.standard,
        reason: '测试环境 standard → 无捕获降级安全（真机走捕获折射）');

    // 外溢不被任何裁剪层吃掉（根因：适配层与包内 Lightweight 均无条件裁剪子级）
    expect(
      find.ancestor(
        of: _expandedRect(tester),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
      reason: '外扩矩形祖先链无 ClipRRect，水珠溢出胶囊可见',
    );

    // 松手回落：恢复原大小的扁平静止胶囊，镜片卸载
    await gesture.up();
    await tester.pumpAndSettle();

    final rest = tester.widget<LiquidBlobLens>(find.byKey(_navBlob));
    expect(rest.activity, 0.0, reason: '松手后弹簧回落到 0');
    expect(rest.width, closeTo(150, 0.5), reason: '宽度回落静止比例');
    expect(_restBackground(tester), findsOneWidget);
    expect(_expandedRect(tester), findsNothing);
    expect(find.byType(GlassEffect), findsNothing);
  });

  testWidgets('捕获边界含胶囊与全部图标、水珠在边界之外', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final lens = _lensOrNull(tester);
    expect(lens, isNotNull);
    final bgKey = lens!.backgroundKey;
    expect(bgKey, isNotNull, reason: '镜片必须显式采样导航边界（body 边界不含图标）');

    final boundary = find.byWidgetPredicate(
      (w) => w is RepaintBoundary && identical(w.key, bgKey),
    );
    expect(boundary, findsOneWidget, reason: '导航自建捕获边界（胶囊+图标）');

    // 图标与胶囊在采样纹理内 → 被镜片采样，划过时图标被物理折射形变
    expect(find.descendant(of: boundary, matching: find.byIcon(Icons.home)),
        findsOneWidget);
    expect(
        find.descendant(
            of: boundary, matching: find.byIcon(Icons.settings_outlined)),
        findsOneWidget);
    expect(find.descendant(of: boundary, matching: find.text('设置')),
        findsOneWidget);
    expect(find.descendant(of: boundary, matching: find.byType(GlassContainer)),
        findsOneWidget,
        reason: '胶囊外壳也在采样纹理内');

    // 水珠镜片不在边界内 → 不自采样，无反馈环
    expect(find.descendant(of: boundary, matching: find.byKey(_navBlob)),
        findsNothing,
        reason: '镜片是边界之外的兄弟层 → 采样绝不含自身');

    // 水珠放行点击给下层图标（镜片盖在图标之上仍可点按/拖动）
    // 根级 IgnorePointer + 淡出 pill 的 IgnorePointer 都在镜片子树内
    expect(
        find.descendant(
            of: find.byKey(_navBlob), matching: find.byType(IgnorePointer)),
        findsWidgets,
        reason: '纯视觉层，点击穿透到图标');
  });

  testWidgets('glassUi 关闭：水珠降级为纯装饰，无包玻璃', (tester) async {
    await _pumpNav(
      tester,
      settings: const AppSettings(glassUi: false),
      onSelect: (_) {},
    );

    expect(_lensOrNull(tester), isNull);
    expect(find.byType(lg.GlassContainer), findsNothing);
    expect(find.byType(GlassContainer), findsOneWidget,
        reason: '胶囊降级纯色外壳仍在导航内');
    // 原装饰不变
    expect(_blobDecoration(tester).color, Colors.white.withValues(alpha: 0.10));
    expect(_blob(tester).height, 50);
    expect(_blob(tester).width, closeTo(150, 0.01),
        reason: '降级装饰同样用静止 0.75 比例宽度');
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
    expect(dragging.width!, greaterThanOrEqualTo(150), reason: '移动只放大不缩小');
    expect(dragging.width!, lessThan(150 * 1.44 + 1),
        reason: '封顶 ×1.44 整体放大，不做横向拉长');
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

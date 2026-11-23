import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

import '../helpers/test_fakes.dart';

/// 698 N17-N19「水滴分裂」动效守卫（jurajkusnier/fluid-bottom-navigation
/// 机制 1:1 + 用户上传视频观感）：三滴常驻融合/裂开、blur+硬阈值液桥、
/// 225° 旋钮、空滴缩没、环脉冲、图标随滴飞。
void main() {
  Widget host({
    AppSettings settings = const AppSettings(),
    int currentIndex = 0,
    required ValueChanged<int> onSelect,
    VoidCallback? onCreateRoom,
    VoidCallback? onJoinRoom,
  }) {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FluidGlassNavBar(
                currentIndex: currentIndex,
                onSelect: onSelect,
                onCreateRoom: onCreateRoom,
                onJoinRoom: onJoinRoom,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// goo 液层液滴视觉中心（含 Transform → 真实坐标）。
  Offset dropCenter(WidgetTester tester, Key key) {
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  /// ＋↔× 旋转矩阵（Transform.rotate(Icon(add)) 的 Z 旋转分量）。
  double centerRotation(WidgetTester tester) {
    final tr = tester.widget<Transform>(find
        .ancestor(
          of: find.byIcon(Icons.add),
          matching: find.byType(Transform),
        )
        .first);
    return tr.transform.storage[0]; // cos(θ)
  }

  group('展开/收起（展开 1150ms / 收回 850ms）', () {
    testWidgets('点＋展开：＋旋 225°（视觉成 ×）、三子滴可点；再点收回禁用',
        (tester) async {
      final calls = <int>[];
      var createCalls = 0;
      var joinCalls = 0;
      await tester.pumpWidget(host(
        onSelect: calls.add,
        onCreateRoom: () => createCalls++,
        onJoinRoom: () => joinCalls++,
      ));

      // 初始：子滴禁用（忽略指针 → 点不着）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[0]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, isEmpty, reason: '收起态子滴不响应');
      expect(createCalls, 0);

      // 点＋ → 展开（1150ms 拉满）。
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        centerRotation(tester),
        closeTo(math.cos(225 * math.pi / 180), 0.02),
        reason: '＋ 旋转 225°（≡45° 视觉成 ×，jurajkusnier 拧劲）',
      );

      // N28 三子滴：开房（弹创建面板）/ 设置（跳 4）/ 加入（弹加入面板）。
      // 点子滴即收起 → 逐次展开逐次点。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[0]),
          warnIfMissed: false);
      await tester.pump();
      expect(createCalls, 1, reason: '开房子滴 → 弹创建房间面板（不切页）');
      expect(calls, isEmpty);

      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, [4], reason: '设置子滴 → 跳设置分支页');

      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[2]),
          warnIfMissed: false);
      await tester.pump();
      expect(joinCalls, 1, reason: '加入子滴 → 弹加入房间面板（不切页）');
      await tester.pump(const Duration(milliseconds: 900));

      // 收起后动作钮禁用、× 逆旋回 ＋。
      final before = calls.length;
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls.length, before, reason: '收回后动作钮禁用');
      expect(centerRotation(tester), closeTo(1.0, 0.02),
          reason: '× 逆旋回 ＋（收回吸收）');
    });

    testWidgets('外部选中设置分支自动展开（Emby/声网已是瓣叶钮不展开）',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(currentIndex: 4, onSelect: calls.add));
      await tester.pump(); // 落 postFrame 自动展开
      await tester.pump(const Duration(milliseconds: 1200));
      // 展开态设置子滴可点（点设置 → 4）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, [4], reason: '自动展开后设置子滴直达分支');

      // Emby/声网分支不触发子滴面板（N28）。
      await tester.pumpWidget(host(currentIndex: 3, onSelect: (_) {}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, [4], reason: '声网分支不自动展开 → 子滴点不着');
    });
  });

  group('水滴分裂（jurajkusnier 三滴常驻机制）', () {
    testWidgets('收起态三滴常驻叠母滴（blur 融合成一滴）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      final m = dropCenter(tester, FluidGlassNavBar.dropMotherKey);
      for (final k in FluidGlassNavBar.dropChildKeys) {
        expect(find.byKey(k), findsOneWidget, reason: '三滴常驻（非淡入）');
        final c = dropCenter(tester, k);
        expect((c - m).distance, lessThan(0.5),
            reason: '收起时三滴叠在母滴位置 → 融合成「一滴」');
      }
    });

    testWidgets('错峰裂开：左→中→右依次飞出（行程投影 0 > 1 > 2）',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      // t ≈ 0.35：左滴已裂出、右滴刚起步。
      await tester.pump(const Duration(milliseconds: 403));
      final m = dropCenter(tester, FluidGlassNavBar.dropMotherKey);
      double prog(int i) {
        final tv = FluidGlassNavBar.childTarget(i, totalWidth: 800) -
            FluidGlassNavBar.motherCenter(totalWidth: 800);
        final c = dropCenter(tester, FluidGlassNavBar.dropChildKeys[i]) - m;
        return (c.dx * tv.dx + c.dy * tv.dy) / tv.distanceSquared;
      }

      expect(prog(0), greaterThan(prog(1)),
          reason: 'Emby(左) 先裂出 > 声网(中)');
      expect(prog(1), greaterThan(prog(2)),
          reason: '声网(中) > 设置(右)（错峰左→右）');
    });

    testWidgets('展开落位：三滴扇形排开（中心略高），图标随滴渐显',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final l = dropCenter(tester, FluidGlassNavBar.dropChildKeys[0]);
      final c = dropCenter(tester, FluidGlassNavBar.dropChildKeys[1]);
      final r = dropCenter(tester, FluidGlassNavBar.dropChildKeys[2]);
      expect(c.dy, lessThan(l.dy), reason: '中心子滴略高（上浮弧线）');
      expect(c.dy, lessThan(r.dy));
      expect(l.dx, lessThan(c.dx));
      expect(r.dx, greaterThan(c.dx));
      // 图标渐显完成（Opacity ≈ 1，jurajkusnier 线性错峰 0.2/0.3/0.4 起）。
      // N28：子滴图标 = 开房（video_call_outlined），随滴飞层定位。
      final iconOpacity = tester.widget<Opacity>(find
          .ancestor(
            of: find.byIcon(FluidGlassNavBar.dropActionIcons[0]),
            matching: find.byType(Opacity),
          )
          .first);
      expect(iconOpacity.opacity, greaterThan(0.9),
          reason: '图标随滴渐显（落位后全亮）');
    });

    testWidgets('点任意子滴：跳页 + 所有子滴收回母滴（自动展开不得复开）',
        (tester) async {
      await tester.pumpWidget(harnessHost());
      await tester.pump();
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      // 点设置子滴 → 跳页 4 + 全部收回。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950));

      final st = tester.state<_NavHarnessState>(find.byType(_NavHarness));
      expect(st.calls, [4], reason: '点子滴跳页（设置 → 分支 4）');
      // 所有子滴收回母滴位（常驻滴叠位融合成一滴）。
      final m = dropCenter(tester, FluidGlassNavBar.dropMotherKey);
      for (final k in FluidGlassNavBar.dropChildKeys) {
        expect((dropCenter(tester, k) - m).distance, lessThan(0.5),
            reason: '点子滴后所有子滴收回母滴');
      }
      // 回归核心（N24 bug 修复）：didUpdateWidget 自动展开不得复开。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(st.calls, [4], reason: '面板保持收起（子滴禁用）——收了不得又开');
    });

    testWidgets('卫星滴零残留（N29 移除）+ 分裂全程只有 3 子滴', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 770)); // t≈0.67 原卫星窗
      expect(find.byKey(const ValueKey('fluidDropSat')), findsNothing,
          reason: '卫星滴已移除（N29 拍板）');
      for (final k in FluidGlassNavBar.dropChildKeys) {
        expect(find.byKey(k), findsOneWidget, reason: '三子滴本体不变');
      }
    });

    testWidgets('瓣叶钮命中区（N29）：均分半瓣宽、满 navHeight——四周无死区',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      final bar = tester.getRect(find.byType(FluidGlassNavBar));
      final navH = FluidGlassNavBar.navHeight;
      for (final label in ['首页', '收藏', 'Emby', '声网']) {
        final hit = find.ancestor(
          of: find.text(label),
          matching: find.byType(GestureDetector),
        );
        final r = tester.getRect(hit.first);
        expect(r.width, greaterThanOrEqualTo(60),
            reason: '$label 命中区 ≥ 半瓣宽（原来 ~44px 内容宽点不到）');
        expect(r.height, greaterThanOrEqualTo(navH - 2),
            reason: '$label 命中区满 navHeight');
        expect(r.bottom, closeTo(bar.bottom, 1.0));
      }
    });
  });

  group('液桥与机制语义（纯函数守卫）', () {
    test('滴体白框助手（N30）：0=无边、1=白 α0.4、线性淡出', () {
      expect(dropSide(0), BorderSide.none,
          reason: '展开子滴完全无边（B 口径拍板）');
      expect(dropSide(0.005), BorderSide.none);
      final full = dropSide(1);
      expect(full.width, 1, reason: '收起态/母滴白框');
      expect(full.color.opacity, closeTo(0.4, 0.01));
      expect(dropSide(0.5).color.opacity, closeTo(0.2, 0.01),
          reason: '分裂中途线性淡出');
    });

    testWidgets('白框随分裂淡出（N30）：收起满框 → 展开落位三子滴无框 → '
        '收回淡回', (tester) async {
      // 收起态：子滴叠位 e=0 → rimAlpha=1 → 满框（融合大滴玻璃边缘感）。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        onSelect: (_) {},
      ));
      await tester.pump();
      final sideOf = (WidgetTester t) {
        final box = t.widget<DecoratedBox>(find
            .descendant(
              of: find.byKey(FluidGlassNavBar.flatDropsKey),
              matching: find.byType(DecoratedBox),
            )
            .first);
        final d = box.decoration as ShapeDecoration;
        return (d.shape as OvalBorder).side;
      };
      expect(sideOf(tester).width, 1, reason: '收起态满框');

      // 展开落位（1150ms 拉满）→ 三子滴 e=1 → rimAlpha=0 → 无框。
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final sides = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.byKey(FluidGlassNavBar.flatDropsKey),
            matching: find.byType(DecoratedBox),
          ))
          .map((b) => ((b.decoration as ShapeDecoration).shape as OvalBorder).side)
          .toList();
      expect(sides.length, 3, reason: '展开落位三子滴');
      for (final side in sides) {
        expect(side, BorderSide.none, reason: '展开子滴零边框（B 口径）');
      }

      // 收回 → 白框淡回。
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(sideOf(tester).width, 1, reason: '收回后白框恢复');
    });

    testWidgets('goo 浓度后置（N28 拉丝回归修复）：液体满不透明参与阈值、'
        '整体浓度在阈值后 Opacity 层', (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(themeColor: 0xFF6750A4),
        onSelect: (_) {},
      ));
      await tester.pump();
      // 结构：gooKey → Opacity(dropFlatOpacity) → ColorFiltered(阈值)。
      final opacity = tester.widget<Opacity>(find
          .descendant(
            of: find.byKey(FluidGlassNavBar.gooKey),
            matching: find.byType(Opacity),
          )
          .first);
      expect(opacity.opacity, FluidGlassNavBar.dropFlatOpacity(0xFF6750A4),
          reason: '浓度（0.40）在阈值后施加——加在阈值前会裁掉液桥细颈');
      // goo 液体圆盘满不透明（阈值 ≈0.39，半透明输入 = 拉丝消失回归）。
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(
          of: find.byKey(FluidGlassNavBar.dropMotherKey),
          matching: find.byType(DecoratedBox)))) {
        final d = box.decoration;
        if (d is BoxDecoration && d.color != null) {
          expect(d.color!.opacity, 1.0,
              reason: '液体圆盘满不透明参与 blur+硬阈值（拉丝机制）');
        }
      }
    });

    test('液桥 = 超大 blur + 硬阈值（jurajkusnier 1:1，无细丝）', () {
      // σ 对子滴视觉半径 ≈0.77×（jurajkusnier σ/R=0.83 同档厚桥）。
      expect(
        FluidGlassNavBar.gooBlurSigma /
            (FluidGlassNavBar.childSize / 2),
        inInclusiveRange(0.5, 1.0),
        reason: '厚液桥：两滴模糊场叠加过阈值才断',
      );
      // jurajkusnier Android 原值**原样直用**（ColorFilter.matrix 偏移列
      // 0..255 制；阈值 0.39、过渡带 0.02 极硬边）。N21 根因修复：
      // 此前误按 0..1 制写 -19.6 → 阈值 0.0015 → 巨型白圈/奶雾。
      expect(FluidGlassNavBar.gooAlphaRow, [0, 0, 0, 50, -5000],
          reason: 'jurajkusnier 原值（0..255 制）');
      // 绘制半径补偿：阈值切回视觉尺寸。
      expect(
        FluidGlassNavBar.gooRadius(FluidGlassNavBar.childSize / 2),
        greaterThan(FluidGlassNavBar.childSize / 2),
        reason: '补偿半径 > 视觉半径',
      );
    });

    test('三滴常驻区间：起点 <1（收起叠母滴融合），左→右错峰', () {
      final s = FluidGlassNavBar.splitStarts;
      final e = FluidGlassNavBar.splitEnds;
      expect(s, [0.0, 0.1, 0.2], reason: 'jurajkusnier 错峰区间（起点即常驻）');
      expect(e, [0.8, 0.9, 1.0]);
      for (var i = 0; i < 3; i++) {
        expect(s[i], lessThan(1.0), reason: '收起时 e=0 叠母滴（非消失）');
        expect(s[i], lessThan(e[i]));
      }
    });

    test('＋ 旋转 225°（jurajkusnier 拧劲）+ 空滴缩没区间', () {
      expect(FluidGlassNavBar.iconRotateDegrees, 225);
      expect(FluidGlassNavBar.iconRotateStart,
          lessThan(FluidGlassNavBar.iconRotateEnd));
      expect(FluidGlassNavBar.shrinkStart,
          lessThan(FluidGlassNavBar.shrinkEnd),
          reason: '中央空滴展开缩没（0.5-0.85）');
      expect(FluidGlassNavBar.shrinkEnd, lessThanOrEqualTo(1.0));
    });

    test('图标渐显区间错峰（0.2/0.3/0.4 → 0.7/0.8/0.9）', () {
      expect(FluidGlassNavBar.iconFadeStarts, [0.2, 0.3, 0.4]);
      expect(FluidGlassNavBar.iconFadeEnds, [0.7, 0.8, 0.9]);
    });

    test('主题色磨砂玻璃配方（N27）：平涂 0.40 / 回退 0.28 / 磨砂 σ5，'
        '无渐变无色散', () {
      expect(FluidGlassNavBar.dropFlatAlpha, 0.40,
          reason: '主题色平涂半透浓度（无渐变单色）');
      expect(FluidGlassNavBar.dropFallbackAlpha, 0.28,
          reason: '未设主题色：银白单色回退');
      expect(FluidGlassNavBar.dropFrostSigma, 5,
          reason: '轻磨砂透底 σ5（背景隐约透出）');
      expect(FluidGlassNavBar.dropRim.opacity, closeTo(0.4, 0.01),
          reason: '细 rim 玻璃边缘感');
      expect(FluidGlassNavBar.dropFlatColor(0xFF6750A4), const Color(0xFF6750A4),
          reason: '滴/goo 纯色 = 主题色本色');
      expect(FluidGlassNavBar.dropFlatColor(null), const Color(0xFFFFFFFF),
          reason: 'null 回退银白单色');
      expect(FluidGlassNavBar.dropFlatOpacity(0xFF6750A4), 0.40);
      expect(FluidGlassNavBar.dropFlatOpacity(null), 0.28);
    });

    testWidgets('磨砂双形态（N27）：开=轻磨砂透底滴、关=平涂滴（零 shader）；'
        '两态零 GlassEffect 折射、零渐变', (tester) async {
      // 玻璃开：磨砂透底滴层。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: true),
        onSelect: (_) {},
      ));
      await tester.pump();
      expect(find.byKey(FluidGlassNavBar.frostedDropsKey), findsOneWidget);
      expect(find.byKey(FluidGlassNavBar.flatDropsKey), findsNothing);
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      // 展开落位三滴分位（去重后 3 个滴体）。
      final frosted = tester.widgetList(find.descendant(
          of: find.byKey(FluidGlassNavBar.frostedDropsKey),
          matching: find.byType(DecoratedBox)));
      expect(frosted.length, 3, reason: '展开落位 3 滴（收起态去重 1 滴）');

      // 玻璃关：平涂滴层、零 shader。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        onSelect: (_) {},
      ));
      await tester.pump();
      expect(find.byKey(FluidGlassNavBar.flatDropsKey), findsOneWidget,
          reason: '玻璃关 = 平涂主题色滴');
      expect(find.byKey(FluidGlassNavBar.frostedDropsKey), findsNothing);

      // N27 核心：两态零折射（GlassEffect 不复存在）。
      expect(find.byType(GlassEffect), findsNothing,
          reason: '折射/色散全去（N27 拍板「折射光影响观感」）');
      // 零渐变：滴体/液体全部单色平涂（Box/Shape 两种装饰均查）。
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(
          of: find.byKey(FluidGlassNavBar.flatDropsKey),
          matching: find.byType(DecoratedBox)))) {
        final d = box.decoration;
        final gradient = switch (d) {
          BoxDecoration() => d.gradient,
          ShapeDecoration() => d.gradient,
          _ => null,
        };
        expect(gradient, isNull, reason: 'N27 无渐变（单色平涂）: $d');
      }
    });

    test('滴/goo 单色跟主题色（N27）：主题本色 + null 回退银白', () {
      const theme = 0xFF6750A4;
      expect(FluidGlassNavBar.dropFlatColor(theme), const Color(theme),
          reason: '主题色本色单色（无渐变）');
      expect(FluidGlassNavBar.dropFlatColor(null), const Color(0xFFFFFFFF),
          reason: 'null → 银白单色回退');
    });

    test('收起更快（反序吸收紧凑）', () {
      expect(FluidGlassNavBar.collapseDuration,
          lessThan(FluidGlassNavBar.expandDuration));
    });
  });
}

/// 带分支 index 状态的宿主（模拟壳层 onSelect 切分支回灌 currentIndex →
/// 触发 didUpdateWidget，N24「自动展开不得复开」回归用）。
Widget harnessHost() {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(const AppSettings())),
  ]);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _NavHarness(),
          ),
        ),
      ),
    ),
  );
}

class _NavHarness extends StatefulWidget {
  const _NavHarness();

  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  int index = 0;
  final List<int> calls = [];

  @override
  Widget build(BuildContext context) {
    return FluidGlassNavBar(
      currentIndex: index,
      onSelect: (i) => setState(() {
        calls.add(i);
        index = i;
      }),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

import '../helpers/test_fakes.dart';

/// 698 N17-N19「水滴分裂」动效守卫（jurajkusnier/fluid-bottom-navigation
/// 机制 1:1 + 用户上传视频观感）：三滴常驻融合/裂开、blur+硬阈值液桥、
/// 225° 旋钮、空滴缩没、环脉冲、图标随滴飞。
void main() {
  Widget host({
    AppSettings settings = const AppSettings(),
    int currentIndex = 0,
    required ValueChanged<int> onSelect,
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
    testWidgets('点＋展开：＋旋 225°（视觉成 ×）、三动作钮可点；再点收回禁用',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(onSelect: calls.add));

      // 初始：动作钮禁用（忽略指针 → 点不着）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[0]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, isEmpty, reason: '收起态动作钮不响应');

      // 点＋ → 展开（1150ms 拉满）。
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        centerRotation(tester),
        closeTo(math.cos(225 * math.pi / 180), 0.02),
        reason: '＋ 旋转 225°（≡45° 视觉成 ×，jurajkusnier 拧劲）',
      );

      // 三动作钮从左到右 = Emby(2) / 声网(3) / 设置(4)。
      // 视频语义：点动作钮即跳页并收起 → 逐次展开逐次点。
      for (var i = 0; i < 3; i++) {
        if (i > 0) {
          await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1200));
        }
        await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[i]),
            warnIfMissed: false);
        await tester.pump();
      }
      expect(calls, [2, 3, 4], reason: '动作语义：Emby/声网/设置');
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

    testWidgets('外部选中动作分支（Emby/声网/设置）自动展开', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(currentIndex: 3, onSelect: calls.add));
      await tester.pump(); // 落 postFrame 自动展开
      await tester.pump(const Duration(milliseconds: 1200));
      // 展开态动作钮可点（点声网 → 3）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, [3], reason: '自动展开后动作钮直达分支');
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
      final iconOpacity = tester.widget<Opacity>(find
          .ancestor(
            of: find.byIcon(ShellNavBar.tabIcons[2]),
            matching: find.byType(Opacity),
          )
          .first);
      expect(iconOpacity.opacity, greaterThan(0.9),
          reason: '图标随滴渐显（落位后全亮）');
    });

    testWidgets('卫星小液滴飞散（分裂末段出现）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 770)); // t≈0.67
      expect(find.byKey(FluidGlassNavBar.dropSatKey), findsOneWidget,
          reason: '视频 f39：分裂末段卫星液滴飞散');
    });
  });

  group('液桥与机制语义（纯函数守卫）', () {
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

    test('复刻色板（视频实测取色）：实心粉渐变 + 磨砂白 30% 条体', () {
      expect(FluidGlassNavBar.dropPinkLight, const Color(0xFFF5B8E3),
          reason: '液滴顶左亮粉（视频核心 233,114,197 同族）');
      expect(FluidGlassNavBar.dropPinkDeep, const Color(0xFFE25EBE),
          reason: '液滴底右深粉（视频底缘 240,107,208 同族）');
      expect(FluidGlassNavBar.barFrostAlpha, 0.30,
          reason: '条体白 30% 叠底（视频 146,131,189 等价）');
    });

    test('收起更快 + 卫星向右上飞散（视频 f39-f43）', () {
      expect(FluidGlassNavBar.collapseDuration,
          lessThan(FluidGlassNavBar.expandDuration));
      final t = FluidGlassNavBar.satelliteTarget(totalWidth: 800);
      expect(t.dx, greaterThan(400), reason: '向右飞散');
      expect(t.dy, lessThan(FluidGlassNavBar.motherCenterY),
          reason: '向上飞散');
    });
  });
}

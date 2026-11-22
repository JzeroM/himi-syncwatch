import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

import '../helpers/test_fakes.dart';

/// 698 N17/N18「水滴分裂」动效守卫（用户上传视频逐帧规格 + 真机反馈）：
/// 涟漪蓄力 → 母滴预拉伸 → gooey 拉丝错峰分裂（长出/细丝/收腰）→ ＋旋× →
/// 卫星液滴 → 图标落位后淡入 → 收回反序吸收（探丝先行）。
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

  group('展开/收起（视频时序：展开 1150ms / 收回 850ms）', () {
    testWidgets('点＋展开：＋旋 45° 成 ×、三动作钮可点；再点收回禁用',
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
      expect(centerRotation(tester), closeTo(math.cos(math.pi / 4), 0.02),
          reason: '＋ 旋转 45° 成 ×（视频 f27）');

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

      // 收起后动作钮禁用、× 逆旋回 ＋（视频 f80）。
      final before = calls.length;
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls.length, before, reason: '收回后动作钮禁用');
      expect(centerRotation(tester), closeTo(1.0, 0.02),
          reason: '× 逆旋回 ＋（收回吸收，视频 f80）');
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

  group('水滴分裂（gooey 拉丝，视频逐帧规格 + N18 高级拉丝）', () {
    testWidgets('错峰：左→中→右依次甩出（中途行程 0 > 1 > 2）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      // t ≈ 0.42：Emby 滴已甩出大半、设置滴刚起步（视频 f31/f33）。
      await tester.pump(const Duration(milliseconds: 480));
      for (final k in FluidGlassNavBar.dropChildKeys) {
        expect(find.byKey(k), findsOneWidget, reason: '三子滴在液层');
      }
      final m = dropCenter(tester, FluidGlassNavBar.dropMotherKey);
      double travel(Key k) => (dropCenter(tester, k) - m).distance;

      expect(travel(FluidGlassNavBar.dropChildKeys[0]),
          greaterThan(travel(FluidGlassNavBar.dropChildKeys[1])),
          reason: 'Emby(左) 行程 > 声网(中)');
      expect(travel(FluidGlassNavBar.dropChildKeys[1]),
          greaterThan(travel(FluidGlassNavBar.dropChildKeys[2])),
          reason: '声网(中) 行程 > 设置(右)（错峰左→右）');
    });

    testWidgets('细丝 pinch-off：行程 75% 断丝（Emby 丝已断、后两滴仍有丝）',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 620)); // t≈0.54
      expect(find.byKey(FluidGlassNavBar.wireKeys[0]), findsNothing,
          reason: 'Emby 滴行程 >75% → 细丝已 pinch-off（发丝级断开）');
      expect(find.byKey(FluidGlassNavBar.wireKeys[1]), findsOneWidget,
          reason: '声网滴细丝仍在（metaball 断后丝相连）');
      expect(find.byKey(FluidGlassNavBar.wireKeys[2]), findsOneWidget,
          reason: '设置滴细丝仍在');
    });

    testWidgets('卫星小液滴飞散（分裂末段出现）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 770)); // t≈0.67
      expect(find.byKey(FluidGlassNavBar.dropSatKey), findsOneWidget,
          reason: '视频 f39：分裂末段卫星液滴飞散');
    });

    testWidgets('落位：三子滴扇形排开（中心略高），图标落位后淡入',
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
      // 图标淡入完成（Opacity ≈ 1）。
      final iconOpacity = tester.widget<Opacity>(find
          .ancestor(
            of: find.byIcon(ShellNavBar.tabIcons[2]),
            matching: find.byType(Opacity),
          )
          .first);
      expect(iconOpacity.opacity, greaterThan(0.9),
          reason: '图标落位后淡入（视频 f41-f45）');
    });
  });

  group('时间线与拉丝语义（纯函数守卫）', () {
    test('错峰单调：子滴 start 递增（左→右），区间互不倒挂', () {
      final s = FluidGlassNavBar.childStarts;
      final e = FluidGlassNavBar.childEnds;
      expect(s.length, 3);
      expect(s[0], lessThan(s[1]));
      expect(s[1], lessThan(s[2]));
      for (var i = 0; i < 3; i++) {
        expect(s[i], lessThan(e[i]), reason: '第 $i 滴起止有序');
      }
    });

    test('涟漪蓄力先于分裂；图标晚于分裂起步（落位后淡入）', () {
      expect(FluidGlassNavBar.ringShrinkEnd,
          lessThanOrEqualTo(FluidGlassNavBar.childStarts[0]),
          reason: '涟漪内收蓄力在分裂之前（视频 f18-f23）');
      expect(FluidGlassNavBar.childIconStart,
          greaterThan(FluidGlassNavBar.childStarts[2]),
          reason: '图标淡入晚于全部分裂起步');
      expect(FluidGlassNavBar.iconRotateStart,
          greaterThanOrEqualTo(FluidGlassNavBar.ringShrinkStart),
          reason: '＋→× 旋转随分裂进行');
    });

    test('收回反序 + 放慢：start 最大者先脱离，收回快于展开', () {
      expect(FluidGlassNavBar.childStarts[2],
          greaterThan(FluidGlassNavBar.childStarts[0]));
      expect(FluidGlassNavBar.collapseDuration,
          lessThan(FluidGlassNavBar.expandDuration),
          reason: '收回 850ms 快于展开 1150ms（N18 放慢灵动）');
    });

    test('细丝宽度单调收细 + pinch-off 发丝级断开', () {
      final w0 = FluidGlassNavBar.wireWidth(0.2);
      final w1 = FluidGlassNavBar.wireWidth(0.5);
      final w2 = FluidGlassNavBar.wireWidth(0.74);
      expect(w0, greaterThan(w1), reason: '单调收细');
      expect(w1, greaterThan(w2));
      expect(w2, lessThan(4), reason: 'pinch 前发丝级（<4dp）');
      expect(FluidGlassNavBar.wireWidth(0.75), 0,
          reason: '行程 75% pinch-off');
      expect(FluidGlassNavBar.wireWidth(0.9), 0);
      expect(FluidGlassNavBar.wirePinch, greaterThan(0.5),
          reason: '细丝晚于行程半程才断（metaball 断后仍有丝相连）');
    });

    test('玻璃液体透明度：折射/磨砂均半透明（非实心白块）', () {
      expect(FluidGlassNavBar.liquidOpacity(true), 0.32,
          reason: '折射态玻璃透感');
      expect(FluidGlassNavBar.liquidOpacity(false), 0.48,
          reason: '磨砂态微浓但仍透');
      expect(FluidGlassNavBar.liquidOpacity(true), lessThan(0.5));
    });

    test('卫星液滴向右上飞散（视频 f39-f43）', () {
      final t = FluidGlassNavBar.satelliteTarget(totalWidth: 800);
      expect(t.dx, greaterThan(400), reason: '向右飞散');
      expect(t.dy, lessThan(FluidGlassNavBar.motherCenterY),
          reason: '向上飞散');
    });
  });
}

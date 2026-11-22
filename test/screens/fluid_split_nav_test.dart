import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

import '../helpers/test_fakes.dart';

/// 698 N17「水滴分裂」动效守卫（用户上传视频逐帧规格 1:1）：
/// 涟漪蓄力 → 母滴预拉伸 → gooey 拉丝错峰分裂 → ＋旋× → 卫星液滴 →
/// 图标落位后淡入 → 收回反序吸收。
void main() {
  Widget host({AppSettings settings = const AppSettings(),
    int currentIndex = 0,
    required ValueChanged<int> onSelect}) {
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

  /// goo 液层内液滴渲染盒中心（含 Transform 位移 → 视觉真实坐标）。
  Offset dropCenter(WidgetTester tester, int i) {
    final boxes = find.descendant(
      of: find.byKey(FluidGlassNavBar.gooKey),
      matching: find.byType(DecoratedBox),
    );
    final box = tester.renderObject<RenderBox>(boxes.at(i));
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  int dropCount(WidgetTester tester) {
    return find
        .descendant(
          of: find.byKey(FluidGlassNavBar.gooKey),
          matching: find.byType(DecoratedBox),
        )
        .evaluate()
        .length;
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

  group('展开/收起（视频时序：展开 0.9s / 收回 0.7s）', () {
    testWidgets('点＋展开：＋旋 45° 成 ×、三动作钮可点；再点收回禁用',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(onSelect: calls.add));

      // 初始：动作钮禁用（忽略指针 → 点不着）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[0]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, isEmpty, reason: '收起态动作钮不响应');

      // 点＋ → 展开（900ms 拉满）。
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950));
      expect(centerRotation(tester), closeTo(math.cos(math.pi / 4), 0.02),
          reason: '＋ 旋转 45° 成 ×（视频 f27）');

      // 三动作钮从左到右 = Emby(2) / 声网(3) / 设置(4)。
      // 视频语义：点动作钮即跳页并收起 → 逐次展开逐次点。
      for (var i = 0; i < 3; i++) {
        if (i > 0) {
          await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 950));
        }
        await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[i]),
            warnIfMissed: false);
        await tester.pump();
      }
      expect(calls, [2, 3, 4], reason: '动作语义：Emby/声网/设置');
      await tester.pump(const Duration(milliseconds: 750));

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
      await tester.pump(const Duration(milliseconds: 950));
      // 展开态动作钮可点（点声网 → 3）。
      await tester.tap(find.byKey(FluidGlassNavBar.actionKeys[1]),
          warnIfMissed: false);
      await tester.pump();
      expect(calls, [3], reason: '自动展开后动作钮直达分支');
    });
  });

  group('水滴分裂（gooey 拉丝，视频逐帧规格）', () {
    testWidgets('错峰：左→中→右依次甩出（中途行程 0 > 1 > 2）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      // t ≈ 0.42：Emby 滴已甩出大半、设置滴刚起步（视频 f31/f33）。
      await tester.pump(const Duration(milliseconds: 380));
      expect(dropCount(tester), 4, reason: '母滴 + 三子滴在液层');
      final m = dropCenter(tester, 0);
      double travel(int i) {
        final c = dropCenter(tester, i);
        return math.sqrt(
            (c.dx - m.dx) * (c.dx - m.dx) + (c.dy - m.dy) * (c.dy - m.dy));
      }

      expect(travel(1), greaterThan(travel(2)),
          reason: 'Emby(左) 行程 > 声网(中)');
      expect(travel(2), greaterThan(travel(3)),
          reason: '声网(中) 行程 > 设置(右)（错峰左→右）');
    });

    testWidgets('卫星小液滴飞散（t≈0.6 五滴：母+3子+卫星）', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 540));
      expect(dropCount(tester), 5, reason: '视频 f39：分裂末段卫星液滴飞散');
    });

    testWidgets('落位：三子滴扇形排开（中心略高），图标落位后淡入',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.tap(find.byKey(FluidGlassNavBar.centerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 950));
      final l = dropCenter(tester, 1);
      final c = dropCenter(tester, 2);
      final r = dropCenter(tester, 3);
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

  group('时间线语义（纯函数守卫）', () {
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

    test('收回反序：start 最大的子滴（设置）先脱离 → 右→中→左吸收', () {
      // 反向播放（controller.reverse）时区间值下降先后 = start 大小反序。
      expect(FluidGlassNavBar.childStarts[2], greaterThan(FluidGlassNavBar.childStarts[0]));
      expect(FluidGlassNavBar.collapseDuration,
          lessThan(FluidGlassNavBar.expandDuration),
          reason: '收回 0.7s 快于展开 0.9s（视频实测）');
    });

    test('卫星液滴向右上飞散（视频 f39-f43）', () {
      final t = FluidGlassNavBar.satelliteTarget(totalWidth: 800);
      expect(t.dx, greaterThan(400), reason: '向右飞散');
      expect(t.dy, lessThan(FluidGlassNavBar.motherCenterY),
          reason: '向上飞散');
    });
  });
}

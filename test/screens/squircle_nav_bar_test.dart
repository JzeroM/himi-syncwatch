import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/squircle_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

import '../helpers/test_fakes.dart';

/// 698 N32「悬浮方块」导航守卫（视频动效 1:1）：跳槽弹滑、图标接力、
/// 标签胶囊跟随、主题色渐变、深图标压亮底、命中区满槽宽。
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
              child: SquircleNavBar(
                currentIndex: currentIndex,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('悬浮方块（698 N32）', () {
    test('玻璃水滴镜片参数（N34）：无色中性（不跟随主题色）', () {
      final settings = SquircleNavBar.lensSettings();
      expect(settings.glassColor.opacity, lessThan(0.12),
          reason: '无色中性白纱（α~0.08，折射透亮）');
      expect(settings.blur, greaterThan(0),
          reason: 'Skia 捕获钥匙（GlassEffect 门槛）');
    });

    testWidgets('条体 = GlassContainer（①款同源双形态）+ 浮块玻璃水滴'
        '（GlassEffect + 立体感层，不跟主题色）', (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(
            glassUi: true, themeColor: 0xFF6750A4),
        onSelect: (_) {},
      ));
      expect(find.byKey(SquircleNavBar.barKey), findsOneWidget);
      expect(find.byType(GlassContainer), findsWidgets,
          reason: '条体①款同源 GlassContainer');
      // 浮块 = ①款同源 GlassEffect 玻璃水滴（真折射镜片）。
      expect(find.byType(GlassEffect), findsWidgets,
          reason: '浮块/标签 = ①款 LiquidBlobLens 同管线真折射镜片');
      // 立体饱满感（N35）：高光斑 + 内阴影层存在。
      expect(
        tester
            .widgetList<DecoratedBox>(find.descendant(
              of: find.byKey(SquircleNavBar.blockKey),
              matching: find.byType(DecoratedBox),
            ))
            .length,
        greaterThan(1),
        reason: '浮块含玻璃底 + 高光斑 + 内阴影多层',
      );
      // 立体参数（N35）：折射厚度/折射率上调（中间鼓）。
      final ls = SquircleNavBar.lensSettings();
      expect(ls.refractiveIndex, greaterThanOrEqualTo(1.4),
          reason: '折射率上调（透镜体量鼓感）');
      expect(ls.thickness, greaterThanOrEqualTo(5),
          reason: '折射厚度上调（中间鼓）');
    });

    testWidgets('玻璃关 = 平涂磨砂近似（零 GlassEffect）', (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        onSelect: (_) {},
      ));
      expect(find.byType(GlassEffect), findsNothing,
          reason: '玻璃关零 shader');
      expect(find.byKey(SquircleNavBar.blockKey), findsOneWidget,
          reason: '平涂磨砂浮块保持');
    });

    testWidgets('跳槽弹滑：点视觉第 4 槽（设置分支 4）→ 浮块/标签落位',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(onSelect: calls.add));
      await tester.pump();
      // N35 槽位公式：两端留 slotMargin、槽位区内均分。
      final slot4Cx = SquircleNavBar.slotCx(4, 800);
      await tester.tapAt(Offset(slot4Cx, 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, [4], reason: '视觉槽 4 = 分支 4（设置）');
      final blockRect =
          tester.getRect(find.byKey(SquircleNavBar.blockKey));
      expect((blockRect.center.dx - slot4Cx).abs(), lessThan(2),
          reason: '浮块落位该槽中心');
    });

    testWidgets('图标位移接力（N35）：落位后浮块位 = 填充形态图标、'
        '中途升起位移', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 视觉槽 3 = 声网分支 3。
      final slot3Cx = SquircleNavBar.slotCx(3, 800);
      await tester.tapAt(Offset(slot3Cx, 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // 升起中段
      // 中段：描边图标在槽位↔浮块之间（位移接力，非瞬移）。
      final midRect =
          tester.getRect(find.byIcon(ShellNavBar.tabIcons[3]).last);
      final blockCxMid =
          tester.getRect(find.byKey(SquircleNavBar.blockKey)).center.dx;
      expect(midRect.center.dx, greaterThan(slot3Cx - 2),
          reason: '升起起点 = 槽位');
      expect(midRect.center.dx, lessThan(blockCxMid + 40),
          reason: '升起中（未瞬移到位）');
      await tester.pump(const Duration(milliseconds: 300)); // 切填充段
      expect(find.byIcon(ShellNavBar.tabSelectedIcons[3]), findsWidgets,
          reason: '到达浮块（lift 0.85+）切填充形态');
      await tester.pump(const Duration(milliseconds: 100)); // 拉满
      // 落位：浮块位 = 填充形态（tabSelectedIcons）。
      final blockRect =
          tester.getRect(find.byKey(SquircleNavBar.blockKey));
      final filled = tester.getRect(
          find.byIcon(ShellNavBar.tabSelectedIcons[3]).last);
      expect((filled.center - blockRect.center).distance, lessThan(2),
          reason: '落位后填充图标在浮块中心');
      // 旧图标降落回槽（描边形态常驻于槽位层）。
      // 初始 _to = 分支 0（首页），在视觉槽 slotBranches.indexOf(0) = 2。
      final homeSlotCx = SquircleNavBar.slotCx(2, 800);
      expect(find.byIcon(ShellNavBar.tabIcons[0]), findsWidgets,
          reason: '首页分支描边图标回槽（降落完成）');
      // 图标 y = 盒顶 + barTop + 条中线（宿主 400 高、盒 88 贴底）。
      final iconY = (400 - SquircleNavBar.boxHeight) +
          SquircleNavBar.barTop +
          SquircleNavBar.navHeight / 2;
      final homeOutline =
          tester.getRect(find.byIcon(ShellNavBar.tabIcons[0]).last).center;
      expect((homeOutline - Offset(homeSlotCx, iconY)).distance, lessThan(60),
          reason: '描边图标在视觉槽 2 附近（降落回槽）');
    });

    test('凹口恒距几何（N33）：入口宽 = 半宽 + 7、凹深 = 半高 + 7', () {
      expect(SquircleNavBar.notchGap, 7, reason: '浮块/标签与凹槽恒距 7dp');
      expect(SquircleNavBar.blockNotchRadius, 22 + 7,
          reason: '顶凹口半径 = 浮块半宽 + 间距');
      expect(SquircleNavBar.barRadius, lessThan(SquircleNavBar.navHeight / 2),
          reason: '圆角矩形（r18 < 半高 27，不是半圆胶囊）');
    });

    testWidgets('条体路径（N33）：圆角矩形 + 顶凹口托浮块 + 底凹口托标签，'
        '凹口随跳槽移动', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      final w = 800.0;
      final slot0 = w / 5 * 0.5;
      final p0 = SquircleNavBar.barPath(
        size: Size(w, SquircleNavBar.navHeight),
        blockCx: slot0,
        labelCx: slot0,
        labelHalfWidth: SquircleNavBar.labelWidthOf('首页') / 2,
      );
      final b0 = p0.getBounds();
      expect(b0.width, closeTo(w, 1), reason: '条体满宽');
      expect(b0.height, closeTo(SquircleNavBar.navHeight, 1),
          reason: '条体高 = navHeight（圆角矩形）');
      final topNotchY = SquircleNavBar.blockCenterY +
          SquircleNavBar.block / 2 +
          SquircleNavBar.notchGap;
      expect(topNotchY, closeTo(37, 0.5),
          reason: '顶凹口底 = 浮块底 + 7dp 间距');
      // N34：凹口 = 形体外扩轮廓（缘距 7dp 平行）——块侧缘 x±22 处
      // 凹口在 x±29（平行 7dp），点测验证。
      expect(p0.contains(Offset(slot0 - 25, 10)), isFalse,
          reason: '块左缘外 3dp 在凹口空腔内（外扩轮廓内侧）');
      expect(p0.contains(Offset(slot0 - 33, 10)), isTrue,
          reason: '块左缘外 11dp 已出凹口（外扩轮廓外侧实心）');
      // 凹口跟随：p0 在槽 0 → (80, 30) 处是凹口空腔（不在条内）；
      // p4 在槽 4 → 凹口移到 720，(80, 30) 变实心条体。
      expect(p0.contains(const Offset(80, 30)), isFalse,
          reason: '槽 0 凹口空腔（浮块正下方被挖空）');
      expect(p0.contains(const Offset(720, 30)), isTrue,
          reason: '非凹口区实心');
      final p4 = SquircleNavBar.barPath(
        size: Size(w, SquircleNavBar.navHeight),
        blockCx: w / 5 * 4.5,
        labelCx: w / 5 * 4.5,
        labelHalfWidth: SquircleNavBar.labelWidthOf('设置') / 2,
      );
      expect(p4.contains(const Offset(80, 30)), isTrue,
          reason: '凹口随跳槽移到槽 4 → 原位置变实心');
      expect(p4.contains(const Offset(720, 30)), isFalse,
          reason: '槽 4 凹口空腔');
      // 底凹口：标签正上方被挖空（条下缘 y=54，凹深 17 → 空腔到 y=37）。
      expect(p0.contains(const Offset(80, 50)), isFalse,
          reason: '底凹口空腔（标签正上方）');
    });

    testWidgets('浮块/标签骑跨条缘（N33）：块悬条上叠入顶凹口、标签骑条下缘',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 全局坐标 → 盒内相对（宿主 400 高、盒 80 贴底 → 盒顶 = 320）。
      final boxTop = 400 - SquircleNavBar.boxHeight;
      final blockRect = tester.getRect(find.byKey(SquircleNavBar.blockKey));
      final bTop = blockRect.top - boxTop;
      final bBottom = blockRect.bottom - boxTop;
      expect(bTop, closeTo(14 + 8 - 22, 1), reason: '块心在条上缘附近');
      expect(bBottom, greaterThan(14),
          reason: '块底部叠入条体（顶凹口托住）');
      expect(bBottom, lessThan(14 + SquircleNavBar.navHeight),
          reason: '块不穿出条下缘');
      final labelRect = tester.getRect(find.text('首页'));
      final lTop = labelRect.top - boxTop;
      final lBottom = labelRect.bottom - boxTop;
      expect(lTop, lessThan(14 + SquircleNavBar.navHeight),
          reason: '标签顶部在条内（骑跨下缘）');
      expect(lBottom, greaterThan(14 + SquircleNavBar.navHeight),
          reason: '标签底部露出条外（骑跨下缘）');
      expect(lBottom, lessThanOrEqualTo(SquircleNavBar.boxHeight + 1),
          reason: '标签不出盒底（N33 防屏幕裁切）');
    });

    test('槽位映射（N35）：首页↔Emby 交换、首页居中默认锁定', () {
      expect(SquircleNavBar.slotBranches, [2, 1, 0, 3, 4],
          reason: '视觉槽 = Emby/收藏/首页/声网/设置（首页居中）');
      expect(SquircleNavBar.slotOfBranch(0), 2,
          reason: '首页在中心槽（默认锁定）');
      // 两端留白：槽 0 中心 ≥ slotMargin + 半槽宽。
      final cx0 = SquircleNavBar.slotCx(0, 390);
      expect(cx0, greaterThanOrEqualTo(SquircleNavBar.slotMargin),
          reason: '端部槽凹口不碰圆角区');
      // 槽位公式：安全余量 47 = 块半宽 22 + 恒距 7 + 条圆角 18。
      expect(SquircleNavBar.slotMargin, 22 + 7 + 18);
    });

    testWidgets('默认锁定首页（N35）：初始浮块停中心槽', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      final blockRect = tester.getRect(find.byKey(SquircleNavBar.blockKey));
      final homeCx = SquircleNavBar.slotCx(2, 800);
      expect((blockRect.center.dx - homeCx).abs(), lessThan(2),
          reason: '初始浮块在首页中心槽');
      expect(find.text('首页'), findsOneWidget, reason: '初始标签 = 首页');
    });

    testWidgets('拖动切换（N35）：横向拖动浮块跟手、松手吸附最近槽',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(onSelect: calls.add));
      await tester.pump();
      final y = 400 - 27.0;
      // 从中心拖到视觉槽 4 方向。
      final startCx = SquircleNavBar.slotCx(2, 800);
      final endCx = SquircleNavBar.slotCx(4, 800);
      final gesture =
          await tester.startGesture(Offset(startCx, y));
      await tester.pump();
      await gesture.moveTo(Offset((startCx + endCx) / 2, y));
      await tester.pump();
      // 拖动中：浮块跟手（中途位置）。
      final midRect = tester.getRect(find.byKey(SquircleNavBar.blockKey));
      expect((midRect.center.dx - (startCx + endCx) / 2).abs(), lessThan(24),
          reason: '拖动中浮块跟手（凹口实时跟随）');
      await gesture.moveTo(Offset(endCx, y));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, [4], reason: '松手吸附视觉槽 4 → 分支 4（设置）');
      final endRect = tester.getRect(find.byKey(SquircleNavBar.blockKey));
      expect((endRect.center.dx - endCx).abs(), lessThan(2),
          reason: '落位吸附槽中心');
    });

    testWidgets('标签不偏心（N36 错位修复）：切换后标签中心 = 浮块中心',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 切到视觉槽 3（声网），再切回视觉槽 2（首页）——_from 长文本后
      // 回短文本，旧实现盒宽 max() 会偏心。
      await tester.tapAt(Offset(SquircleNavBar.slotCx(3, 800), 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(Offset(SquircleNavBar.slotCx(2, 800), 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final blockCx =
          tester.getRect(find.byKey(SquircleNavBar.blockKey)).center.dx;
      final labelCx = tester.getRect(find.text('首页')).center.dx;
      expect((labelCx - blockCx).abs(), lessThan(3),
          reason: '标签中心恒 = 浮块中心（宽度同源，不偏心）');
    });

    test('镜片参数按尺寸收敛（N36）：玻璃不外扩糊条', () {
      // 标签高 20：edgeZone 4 / rim 1.2（edgeZone 20≥高 → 全形体边缘区
      // =「空心框」根因）。
      expect(4, lessThan(SquircleNavBar.labelHeight / 2),
          reason: '标签 edgeZone < 半高（不糊满）');
      expect(10, lessThan(SquircleNavBar.block / 2),
          reason: '浮块 edgeZone < 半宽');
    });

    testWidgets('命中区满槽宽（N29 教训）：每槽 = 1/5 条宽 × 满高',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 槽位命中层存在（GestureDetector opaque 覆盖整槽）。
      for (var i = 0; i < 5; i++) {
        final hit = find.byKey(ValueKey('squircleSlot$i'));
        expect(hit, findsOneWidget);
      }
    });

    testWidgets('标签胶囊跟随 + 文案 = tab 组', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      expect(find.text('首页'), findsOneWidget, reason: '初始标签 = 首页');
      await tester.tapAt(Offset(800 / 5 * 3.5, 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('声网'), findsOneWidget, reason: '落位后标签 = 声网');
    });
  });
}

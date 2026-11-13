import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/horizontal_row_coordinator.dart';

/// 688：滚动手感打磨。
///
/// ## 三个问题
///
/// 1. **桌面细滚动条不好看** → 删掉 `buildScrollbar` 覆写，回归默认
/// 2. **打开软件首页不在开头** → `PageStorageKey` 会把滚动偏移
///    **跨启动持久化**到磁盘；改用页面级 `ScrollController` + 切 tab
///    时主动 `jumpTo(0)`
/// 3. **横向栏错位观感差** → 滚 B 栏时 A 栏平滑回正（697 起 420ms）
///
/// ## 附带修复「上下滑动不舒服」
///
/// - 页面级 `AlwaysScrollableScrollPhysics()` 覆盖了全局 Bouncing 回弹
///   （回弹根本没生效）→ 删除 6 处，让全局配置生效
/// - `cacheExtent: 600` 过大反而增加单帧布局开销 → 降到 250
/// - `StaggerReveal` 用 index 作 key，滚动回收后可能重播淡入 →
///   改用 item id
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String scrollBehavior;
  late String homeScreen;
  late String categoryScreen;
  late String staggerReveal;

  setUpAll(() {
    scrollBehavior = read('lib/core/scroll_behavior.dart');
    homeScreen = read('lib/screens/home/home_screen.dart');
    categoryScreen = read('lib/screens/category/category_screen.dart');
    staggerReveal = read('lib/widgets/stagger_reveal.dart');
  });

  // ═══════════════════════════════════════════════════════════════
  // A. 桌面滚动条
  // ═══════════════════════════════════════════════════════════════

  group('A 桌面滚动条', () {
    test('A1 不再覆写 buildScrollbar（回归 Flutter 默认）', () {
      // 剔除注释后判定（注释里会提到「不覆写 buildScrollbar」）
      final code = scrollBehavior
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('*');
          })
          .join('\n');
      expect(code, isNot(contains('Widget buildScrollbar')));
      expect(code, isNot(contains('Scrollbar(')));
    });

    test('A2 保留回弹与鼠标拖动设置', () {
      expect(scrollBehavior, contains('BouncingScrollPhysics'));
      expect(scrollBehavior, contains('ClampingScrollPhysics'));
      expect(scrollBehavior, contains('PointerDeviceKind.mouse'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 首页初始位置 + 切 tab 回顶部
  // ═══════════════════════════════════════════════════════════════

  group('B 首页滚动位置', () {
    test('B1 不再用 PageStorageKey（会跨启动持久化）', () {
      expect(homeScreen, isNot(contains("PageStorageKey('homeMainList')")));
    });

    test('B2 改用页面级 ScrollController', () {
      expect(homeScreen, contains('final ScrollController _homeScrollController'));
      expect(homeScreen, contains('controller: _homeScrollController'));
    });

    test('B3 切回首页时 jumpTo(0)', () {
      expect(homeScreen, contains('_homeScrollController.jumpTo(0)'));
      expect(homeScreen, contains('shellBranchEpochProvider.select((m) => m[0] ?? 0)'));
    });

    test('B4 controller 在 dispose 释放（防泄漏）', () {
      expect(homeScreen, contains('_homeScrollController.dispose()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 横向栏互斥回正
  // ═══════════════════════════════════════════════════════════════

  group('C 横向栏互斥回正', () {
    testWidgets('C1 滚 B 栏时 A 栏回正到 0', (tester) async {
      final coord = HorizontalRowCoordinator();
      final a = ScrollController();
      final b = ScrollController();
      coord.register(a);
      coord.register(b);
      addTearDown(() {
        a.dispose();
        b.dispose();
      });

      // 必须挂到真实可滚动 widget 上，controller 才有 clients
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                height: 60,
                child: ListView.builder(
                  controller: a,
                  scrollDirection: Axis.horizontal,
                  itemCount: 20,
                  itemBuilder: (_, i) =>
                      SizedBox(width: 100, child: Text('A$i')),
                ),
              ),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  controller: b,
                  scrollDirection: Axis.horizontal,
                  itemCount: 20,
                  itemBuilder: (_, i) =>
                      SizedBox(width: 100, child: Text('B$i')),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // A 已滚到 120
      a.jumpTo(120);
      await tester.pump();
      expect(a.offset, 120);

      // 激活 B → A 应回正
      coord.activate(b, reduced: true);
      await tester.pump();
      expect(a.offset, 0);
    });

    test('C2 回正动画 420ms easeInOutCubic（697 放缓）', () {
      // 697：260ms + easeOutCubic 体感「起步猛、后面拖」——
      // easeOutCubic 在 t=0.33 时已完成 70% 位移，用户刚碰到 B 栏，
      // A 栏就窜回大半。改为 420ms + easeInOutCubic（两头都有缓冲）。
      expect(HorizontalRowCoordinator.restoreDuration,
          const Duration(milliseconds: 420));
      final src = read('lib/widgets/horizontal_row_coordinator.dart');
      expect(src, contains('Curves.easeInOutCubic'));
      // 不得回退到旧的「起步猛」曲线
      expect(src, isNot(contains('Curves.easeOutCubic')));
    });

    test('C3 只在用户主动滚动时激活（程序性 jumpTo 不触发）', () {
      final row = read('lib/widgets/hover_scroll_row.dart');
      expect(row, contains('position.isScrollingNotifier.value'));
    });

    test('C4 减少动画时直接 jumpTo（无过渡）', () {
      final src = read('lib/widgets/horizontal_row_coordinator.dart');
      expect(src, contains('if (reduced)'));
      expect(src, contains('other.jumpTo(0)'));
    });

    test('C5 外部 controller 的栏不参与（保护详情页自动定位）', () {
      final row = read('lib/widgets/hover_scroll_row.dart');
      expect(row, contains('if (_ownsController) {'));
    });

    test('C6 只在首页挂作用域（分类/详情不做）', () {
      expect(homeScreen, contains('HorizontalRowCoordinatorScope('));
      expect(categoryScreen, isNot(contains('HorizontalRowCoordinatorScope(')));
      final detail = read('lib/screens/detail/detail_screen.dart');
      expect(detail, isNot(contains('HorizontalRowCoordinatorScope(')));
    });

    test('C7 注销时清理（防悬挂引用）', () {
      final coord = HorizontalRowCoordinator();
      final c = ScrollController();
      coord.register(c);
      expect(coord.registeredCount, 1);
      coord.unregister(c);
      expect(coord.registeredCount, 0);
      expect(coord.active, isNull);
      c.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 上下滑动不适修复
  // ═══════════════════════════════════════════════════════════════

  group('D 上下滑动', () {
    test('D1 页面级不再覆盖 AlwaysScrollableScrollPhysics（回弹才生效）', () {
      for (final p in [
        'lib/screens/home/home_screen.dart',
        'lib/screens/favorites/favorites_screen.dart',
        'lib/screens/home/tmdb_home_view.dart',
        'lib/screens/tmdb/tmdb_grid_screen.dart',
      ]) {
        expect(read(p), isNot(contains('physics: const AlwaysScrollableScrollPhysics()')),
            reason: '$p 仍覆盖全局 physics，回弹不生效');
      }
    });

    test('D2 cacheExtent 从 600 降到 250', () {
      expect(homeScreen, contains('cacheExtent: 250'));
      expect(homeScreen, isNot(contains('cacheExtent: 600')));
    });

    test('D3 StaggerReveal 支持稳定 itemKey', () {
      expect(staggerReveal, contains('this.itemKey'));
      expect(staggerReveal, contains('widget.itemKey ?? widget.index'));
    });

    test('D4 分类页传 item id 而非 index', () {
      expect(categoryScreen, contains('itemKey: _items[index].id'));
    });
  });
}

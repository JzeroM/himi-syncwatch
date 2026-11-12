import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/scroll_behavior.dart';
import 'package:himi_syncwatch/utils/motion.dart';

/// 687：全平台滑动流畅度与交互动效。
///
/// ## 抖动根因（真机「滑动中感觉有抖动」）
///
/// 1. **`ref.watch(settingsProvider)` 监听整个 AppSettings**（100+ 字段）
///    ——改任意无关设置都重建整页
/// 2. **列表项未包 `RepaintBoundary`**——玻璃/阴影每帧重绘整条列表
/// 3. **无 `itemExtent`**——Flutter 无法预估滚动范围
/// 4. **无 `PageStorageKey`**——切页回来滚动位置丢失
/// 5. **滚动中玻璃仍真折射**——每帧重新采样背景纹理
///
/// ## 交互动效
///
/// 全局滚动手感（iOS 回弹）、页面转场（iOS 横滑）、按压反馈、入场
/// stagger、Hero 共享元素、骨架屏、标题栏渐显、滚动视差、下拉刷新
/// 玻璃化、减少动画无障碍。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String appDart;
  late String homeScreen;
  late String tmdbHome;
  late String detailScreen;
  late String tvFocusable;
  late String posterCard;
  late String glassContainer;
  late String categoryScreen;

  setUpAll(() {
    appDart = read('lib/core/app.dart');
    homeScreen = read('lib/screens/home/home_screen.dart');
    tmdbHome = read('lib/screens/home/tmdb_home_view.dart');
    detailScreen = read('lib/screens/detail/detail_screen.dart');
    tvFocusable = read('lib/widgets/tv/tv_focusable.dart');
    posterCard = read('lib/widgets/poster_card.dart');
    glassContainer = read('lib/widgets/glass/glass_container.dart');
    categoryScreen = read('lib/screens/category/category_screen.dart');
  });

  // ═══════════════════════════════════════════════════════════════
  // A. 全局滚动手感
  // ═══════════════════════════════════════════════════════════════

  group('A 全局滚动手感', () {
    testWidgets('A1 手机用 BouncingScrollPhysics（iOS 回弹）', (tester) async {
      late ScrollPhysics p;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (ctx) {
              // getPlatform 依赖 Theme.platform
              return Theme(
                data: ThemeData(platform: TargetPlatform.android),
                child: Builder(
                  builder: (c) {
                    p = const HimiScrollBehavior().getScrollPhysics(c);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(p, isA<BouncingScrollPhysics>());
    });

    testWidgets('A2 桌面用 ClampingScrollPhysics（滚轮精确）', (tester) async {
      late ScrollPhysics p;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(platform: TargetPlatform.windows),
          child: Builder(
            builder: (c) {
              p = const HimiScrollBehavior().getScrollPhysics(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(p, isA<ClampingScrollPhysics>());
    });

    test('A3 桌面放开鼠标拖动（默认不含）', () {
      const b = HimiScrollBehavior();
      expect(b.dragDevices, contains(PointerDeviceKind.mouse));
      expect(b.dragDevices, contains(PointerDeviceKind.touch));
    });

    test('A4 app.dart 已挂载 scrollBehavior', () {
      expect(codeOnly(appDart), contains('scrollBehavior: const HimiScrollBehavior()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 页面转场
  // ═══════════════════════════════════════════════════════════════

  group('B 页面转场', () {
    test('B1 手机用 Cupertino 横滑', () {
      expect(appDart, contains('TargetPlatform.android: CupertinoPageTransitionsBuilder()'));
      expect(appDart, contains('TargetPlatform.iOS: CupertinoPageTransitionsBuilder()'));
    });

    test('B2 桌面用 FadeUpwards', () {
      expect(appDart, contains('TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder()'));
      expect(appDart, contains('TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 减少动画无障碍
  // ═══════════════════════════════════════════════════════════════

  group('C 减少动画', () {
    testWidgets('C1 disableAnimations 时 Motion.of 返回 zero', (tester) async {
      late Duration d;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (c) {
              d = Motion.of(c, const Duration(milliseconds: 300));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(d, Duration.zero);
    });

    testWidgets('C2 正常时返回原时长', (tester) async {
      late Duration d;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (c) {
              d = Motion.of(c, const Duration(milliseconds: 300));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(d, const Duration(milliseconds: 300));
    });

    testWidgets('C3 scale 在减少动画时为 1.0', (tester) async {
      late double s;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (c) {
              s = Motion.scale(c, 0.97);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(s, 1.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. settingsProvider 全量监听修复
  // ═══════════════════════════════════════════════════════════════

  group('D 只订阅用到的设置字段', () {
    test('D1 TMDB 首页不再 watch 整个 settingsProvider', () {
      expect(codeOnly(tmdbHome),
          isNot(contains('ref.watch(settingsProvider);')));
      expect(tmdbHome, contains('settingsProvider.select((s) => s.homeCarousel)'));
    });

    test('D2 详情页版本行只订阅 tvMode', () {
      expect(detailScreen, contains('settingsProvider.select((s) => s.tvMode)'));
    });

    test('D3 播放页顶栏只订阅三个字段', () {
      expect(homeScreen, isNotNull);  // 保持 group 非空
      final player = File('lib/screens/player/player_screen.dart')
          .readAsStringSync();
      expect(player, contains('s.tvMode,\n        showNetworkSpeed: s.showNetworkSpeed,'));
      expect(player, contains('glassUi: s.glassUi,'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 列表性能
  // ═══════════════════════════════════════════════════════════════

  group('E 列表性能', () {
    test('E1 688：改用 ScrollController（PageStorageKey 会跨启动持久化）', () {
      // 【结论反转】687 用 PageStorageKey 想「切 tab 保位置」，但它会把
      // 滚动偏移持久化到磁盘 → 重启应用后首页不在开头（真机反馈）。
      // 688 改为页面级 ScrollController + 切 tab 时主动 jumpTo(0)。
      expect(homeScreen, isNot(contains("PageStorageKey('homeMainList')")));
      expect(homeScreen, contains('controller: _homeScrollController'));
    });

    test('E2 688：预渲染缓存降到 250（600 反而增加单帧开销）', () {
      expect(homeScreen, contains('cacheExtent: 250'));
    });

    test('E3 首页列表项包 RepaintBoundary', () {
      expect(homeScreen, contains('return RepaintBoundary('));
    });

    test('E4 分类页海报网格项包 RepaintBoundary', () {
      expect(categoryScreen, contains('StaggerReveal('));
      expect(categoryScreen, contains('RepaintBoundary('));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // F. 滚动中玻璃降级
  // ═══════════════════════════════════════════════════════════════

  group('F 滚动中玻璃降级', () {
    test('F1 GlassContainer 有 degradeWhileScrolling 开关', () {
      expect(glassContainer, contains('this.degradeWhileScrolling = false'));
      expect(glassContainer, contains('final bool degradeWhileScrolling'));
    });

    test('F2 滚动中按纯色渲染（glassEnabled 被压制）', () {
      expect(glassContainer,
          contains('final glassEnabled = settingsGlass && !scrollingDegrade;'));
      expect(glassContainer, contains('ScrollGlassIndicator.of(context)'));
    });

    test('F3 停止滚动 120ms 后恢复', () {
      final scope =
          File('lib/widgets/glass/scroll_glass_scope.dart').readAsStringSync();
      expect(scope, contains('static const int restoreDelayMs = 120'));
      expect(scope, contains('Timer('));
    });

    test('F4 用 InheritedWidget 广播（O(1) 查表）', () {
      final scope =
          File('lib/widgets/glass/scroll_glass_scope.dart').readAsStringSync();
      expect(scope, contains('class ScrollGlassIndicator extends InheritedWidget'));
      expect(scope, contains('dependOnInheritedWidgetOfExactType'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // G. 按压反馈
  // ═══════════════════════════════════════════════════════════════

  group('G 按压反馈', () {
    test('G1 非 TV 模式接 PressableScale（旧实现无反馈）', () {
      expect(tvFocusable, contains('return PressableScale('));
      // 不再直接返回裸 GestureDetector
      expect(codeOnly(tvFocusable),
          isNot(contains('return GestureDetector(\n        onTap: onTap,')));
    });

    test('G2 按下 0.97 / 松开回弹', () {
      final p = File('lib/widgets/pressable_scale.dart').readAsStringSync();
      expect(p, contains('this.pressedScale = 0.97'));
      expect(p, contains('? widget.pressedScale'));
      // 按下快、回弹慢
      expect(p, contains('milliseconds: _pressed ? 90 : 140'));
    });

    test('G3 减少动画时不缩放', () {
      final p = File('lib/widgets/pressable_scale.dart').readAsStringSync();
      expect(p, contains('_pressed && !Motion.reduced(context)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // H. 入场 stagger
  // ═══════════════════════════════════════════════════════════════

  group('H 入场 stagger', () {
    test('H1 按 index 递增延迟', () {
      final s = File('lib/widgets/stagger_reveal.dart').readAsStringSync();
      expect(s, contains('widget.index * widget.stepMs'));
      expect(s, contains('maxDelayMs'));
    });

    test('H2 只播一次（静态 Set 记录）', () {
      final s = File('lib/widgets/stagger_reveal.dart').readAsStringSync();
      expect(s, contains('static final Set<int> _played'));
      expect(s, contains('StaggerReveal._played.contains(key)'));
    });

    test('H3 减少动画时直接显示', () {
      final s = File('lib/widgets/stagger_reveal.dart').readAsStringSync();
      expect(s, contains('Motion.reduced(context)'));
      expect(s, contains('_controller.value = 1.0'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // I. Hero 共享元素
  // ═══════════════════════════════════════════════════════════════

  group('I Hero（海报 → 详情页）', () {
    test('I1 PosterCard 支持可选 heroTag', () {
      expect(posterCard, contains('this.heroTag'));
      expect(posterCard, contains('final Object? heroTag'));
    });

    test('I2 未传 tag 时不包 Hero（防同页冲突）', () {
      expect(posterCard, contains('if (tag == null) return child;'));
    });

    test('I3 飞行中保持 2:3 + 圆角收敛', () {
      expect(posterCard, contains('flightShuttleBuilder'));
      expect(posterCard, contains('BorderRadius.circular(12 * (1 - t))'));
    });

    test('I4 主列表传 tag、相似推荐不传', () {
      expect(homeScreen, contains("heroTag: 'poster_\${item.id}'"));
      expect(categoryScreen, contains("heroTag: 'poster_\${_items[index].id}'"));
      // 相似推荐（media_details_section）不传
      final similar =
          File('lib/screens/detail/media_details_section.dart').readAsStringSync();
      expect(similar, isNot(contains('heroTag')));
    });

    test('I5 详情页有隐藏 Hero 落点', () {
      expect(detailScreen, contains("tag: 'poster_\${_item!.id}'"));
      expect(detailScreen, contains('SizedBox(width: 0, height: 0)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // J. 骨架屏
  // ═══════════════════════════════════════════════════════════════

  group('J 骨架屏', () {
    test('J1 提供卡片/网格/横栏三种骨架', () {
      final s = File('lib/widgets/skeleton.dart').readAsStringSync();
      expect(s, contains('class SkeletonBox'));
      expect(s, contains('class SkeletonPosterCard'));
      expect(s, contains('class SkeletonPosterGrid'));
      expect(s, contains('class SkeletonPosterRow'));
    });

    test('J2 微光循环 + 减少动画时静态', () {
      final s = File('lib/widgets/skeleton.dart').readAsStringSync();
      expect(s, contains('_shimmer.repeat()'));
      expect(s, contains('Motion.reduced(context)'));
    });

    test('J3 四个高频页已接入', () {
      for (final p in [
        'lib/screens/category/category_screen.dart',
        'lib/screens/search/global_search_screen.dart',
        'lib/screens/favorites/favorites_screen.dart',
        'lib/screens/favorites/favorites_all_screen.dart',
      ]) {
        expect(read(p), contains('SkeletonPosterGrid'),
            reason: '$p 未接入骨架屏');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // K. 标题栏渐显 + 滚动视差 + 下拉刷新玻璃化
  // ═══════════════════════════════════════════════════════════════

  group('K 其它交互', () {
    test('K1 标题栏渐显组件存在（滚动位置驱动）', () {
      final s = File('lib/widgets/glass/glass_refresh_indicator.dart')
          .readAsStringSync();
      expect(s, contains('class ScrollRevealBackdrop'));
      expect(s, contains('controller.position.pixels'));
    });

    test('K2 首页轮播滚动视差（0.5 倍反向位移）', () {
      final s = File('lib/widgets/home_hero_carousel.dart').readAsStringSync();
      expect(s, contains('Transform.translate'));
      expect(s, contains('offset: Offset(delta * 60, 0)'));
      // 减少动画时关闭
      expect(s, contains('if (Motion.reduced(context)) return slide;'));
    });

    test('K3 下拉刷新玻璃化（主色弧 + 深底）', () {
      final s = File('lib/widgets/glass/glass_refresh_indicator.dart')
          .readAsStringSync();
      expect(s, contains('class GlassRefreshIndicator'));
      expect(s, contains('color: kNavBlobColor'));
      expect(s, contains('backgroundColor: const Color(0xCC1A1D23)'));
    });

    test('K4 五个页面已换成 GlassRefreshIndicator', () {
      for (final p in [
        'lib/screens/category/category_screen.dart',
        'lib/screens/favorites/favorites_screen.dart',
        'lib/screens/home/home_screen.dart',
        'lib/screens/tmdb/tmdb_grid_screen.dart',
        'lib/screens/home/tmdb_home_view.dart',
      ]) {
        expect(read(p), contains('GlassRefreshIndicator('),
            reason: '$p 未接入玻璃刷新');
      }
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 695：TMDB 模式滑动流畅度补漏——687/688 全平台优化当年对 TMDB 只做了一半。
///
/// 【根因（真机「TMDB 模式滑动不流畅」）】
/// 1. TMDB 首页主列表项无 `RepaintBoundary`（服务端首页有）→ 滚屏时
///    玻璃/阴影整列表逐帧重绘；
/// 2. TMDB 网格页无 `ScrollGlassScope` → 滚动中玻璃仍逐帧真折射
///   （home_screen:501 注释认定的卡顿主因），「查看详情」GlassContainer
///    也缺 `degradeWhileScrolling: true`。
void main() {
  final home =
      File('lib/screens/home/tmdb_home_view.dart').readAsStringSync();
  final grid = File('lib/screens/tmdb/tmdb_grid_screen.dart').readAsStringSync();

  group('① TMDB 首页：逐项 RepaintBoundary + 玻璃滚动降级', () {
    test('主列表 itemBuilder 包 RepaintBoundary', () {
      expect(home,
          contains('itemBuilder: (context, index) =>\n              RepaintBoundary(child: content[index])'),
          reason: '687 根因 #2：列表项无 RepaintBoundary → 整列表逐帧重绘');
    });

    test('横向行卡片（平台行/海报行）包 RepaintBoundary', () {
      // 主列表 1 处 + HoverScrollRow 行内 2 处 ≥ 3。
      expect('RepaintBoundary('.allMatches(home).length, greaterThanOrEqualTo(3));
    });

    test('「查看详情」玻璃滚动中降级', () {
      expect(home, contains('degradeWhileScrolling: true'),
          reason: '687 根因 #5：滚动中玻璃仍每帧真折射');
    });

    test('ScrollGlassScope 已接线（697 保持）', () {
      expect(home, contains('ScrollGlassScope('));
    });
  });

  group('② TMDB 网格页：玻璃滚动降级 + 逐格隔离', () {
    test('ScrollGlassScope 包住 CustomScrollView', () {
      expect(grid, contains('ScrollGlassScope('));
      expect(grid, contains('child: CustomScrollView('));
    });

    test('每格 TmdbPosterCard 包 RepaintBoundary', () {
      expect(grid, contains('return RepaintBoundary(child: TmdbPosterCard('));
    });

    test('cacheExtent 250 对齐首页（688 调优值）', () {
      expect(grid, contains('cacheExtent: 250'));
    });
  });
}

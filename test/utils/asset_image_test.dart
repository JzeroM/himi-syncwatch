import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/asset_image.dart';

/// 681：资源图按显示尺寸解码（`cacheWidth`）+ post-frame 预热。
///
/// ## 为什么需要
///
/// `Image.asset` 不带 `cacheWidth` 时按**原图分辨率**解码，且
/// `instantiateImageCodec` 在 UI 线程同步执行。实测两处明显卡顿：
///
/// - 声网页 4 张截图（175 KB）首次切标签时同步解码 20~80ms
/// - TMDB 首页 7 张平台 logo（89 KB，`disney_plus` 单张 65 KB）在
///   **启动首屏**解码 → 拖慢首页渲染
///
/// 修复：`cacheWidth = 显示宽 × dpr`（clamp 1..2048）+ post-frame 预热。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('A cacheWidth 计算', () {
    testWidgets('A1 cacheWidth = 显示宽 × dpr', (tester) async {
      late int w1, w2, w3;
      for (final entry in <(double, int)>[
        (1.0, 100),
        (2.0, 200),
        (3.0, 300),
      ]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(devicePixelRatio: entry.$1),
            child: Builder(
              builder: (ctx) {
                final w = cacheWidthFor(ctx, 100);
                if (entry.$1 == 1.0) w1 = w;
                if (entry.$1 == 2.0) w2 = w;
                if (entry.$1 == 3.0) w3 = w;
                return const SizedBox();
              },
            ),
          ),
        );
      }
      expect(w1, 100);
      expect(w2, 200);
      expect(w3, 300);
    });

    testWidgets('A2 上限 clamp 2048（超大屏不解码巨图）', (tester) async {
      late int w;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 4.0),
          child: Builder(
            builder: (ctx) {
              w = cacheWidthFor(ctx, 2000); // 2000*4 = 8000 → clamp
              return const SizedBox();
            },
          ),
        ),
      );
      expect(w, 2048);
    });

    testWidgets('A3 下限 clamp 1（未布局 0 宽不崩）', (tester) async {
      late int w;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2.0),
          child: Builder(
            builder: (ctx) {
              w = cacheWidthFor(ctx, 0);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(w, 1);
    });
  });

  group('B 辅助函数行为', () {
    testWidgets('B1 assetImage 带 cacheWidth 且按显示宽算', (tester) async {
      late Image img;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2.0),
          child: Builder(
            builder: (ctx) {
              img = assetImage(ctx, 'assets/images/platforms/netflix.png',
                  displayWidth: 50);
              return const SizedBox();
            },
          ),
        ),
      );
      // Image.asset 内部把 cacheWidth 包成 ResizeImage
      final provider = img.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 100);
    });

    test('B2 源码：预热与渲染共用 cacheWidthFor（防解码两份）', () {
      final src = read('lib/utils/asset_image.dart');
      // 两个入口都必须走 cacheWidthFor
      final uses = RegExp(r'cacheWidthFor\(').allMatches(src).length;
      expect(uses, greaterThanOrEqualTo(2),
          reason: 'assetImage 与 precacheAssetImage 必须共用同一计算');
      expect(src, contains('precacheImage(ResizeImage(AssetImage(path)'));
    });

    testWidgets('B3 预热在 post-frame 调度（不抢首帧）', (tester) async {
      final scheduled = <VoidCallback>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Builder(
            builder: (ctx) {
              precacheAssetImagesAfterFrame(
                ctx,
                const ['a.png', 'b.png'],
                displayWidth: 52,
                onSchedule: scheduled.add,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      // 注入的调度器收到回调（生产走 addPostFrameCallback）
      expect(scheduled, hasLength(1));
    });
  });

  group('C 调用点全部改用辅助函数', () {
    test('C1 声网截图：LayoutBuilder + assetImage', () {
      final src = read('lib/widgets/agora/agora_book_page.dart');
      expect(src, contains('assetImage('));
      expect(src, contains('LayoutBuilder'));
      expect(src, isNot(contains('Image.asset(')));
    });

    test('C2 声网全屏查看：assetImage 用全屏宽', () {
      final src = read('lib/screens/agora/agora_config_screen.dart');
      expect(src, contains('assetImage('));
      expect(src, contains('MediaQuery.sizeOf(context).width'));
      expect(src, isNot(contains('Image.asset(')));
    });

    test('C3 声网页 post-frame 预热 4 张截图', () {
      final src = read('lib/screens/agora/agora_config_screen.dart');
      expect(src, contains('precacheAssetImagesAfterFrame'));
      expect(src, contains('agoraGuideSteps'));
    });

    test('C4 外观图标：assetImage 按 64 解码', () {
      final src = read('lib/screens/settings/appearance_settings_screen.dart');
      expect(src, contains('assetImage('));
      expect(src, contains('displayWidth: _size'));
      expect(src, isNot(contains('Image.asset(')));
    });

    test('C5 TMDB 标题 logo：cacheWidthFor(26 * 2)', () {
      final src = read('lib/screens/tmdb/tmdb_grid_screen.dart');
      expect(src, contains('cacheWidthFor(context, 26 * 2)'));
    });

    test('C6 TMDB 平台卡 logo：cacheWidthFor(logoHeight * 2)', () {
      final src = read('lib/widgets/tmdb_platform_card.dart');
      expect(src, contains('cacheWidthFor(context, platform.logoHeight * 2)'));
    });

    test('C7 TMDB 首页 post-frame 预热 7 张平台 logo', () {
      final src = read('lib/screens/home/tmdb_home_view.dart');
      expect(src, contains('precacheAssetImagesAfterFrame'));
      expect(src, contains('tmdbPlatforms.map((p) => p.logoAsset)'));
      // 宽度与渲染侧一致（52 = 26 * 2）
      expect(src, contains('displayWidth: 52'));
    });
  });

  group('D 预热宽度与渲染宽度一致（防双份解码）', () {
    test('D1 TMDB：预热 52 = 渲染 logoHeight(26) × 2', () {
      final card = read('lib/widgets/tmdb_platform_card.dart');
      final home = read('lib/screens/home/tmdb_home_view.dart');
      // 渲染侧按 logoHeight*2 算，预热侧固定 52（覆盖最大 logoHeight 26）
      expect(card, contains('logoHeight * 2'));
      expect(home, contains('displayWidth: 52'));
      // 平台定义里最大 logoHeight 应为 26（超出则预热宽度不够）
      final model = read('lib/models/tmdb_platform.dart');
      final heights = RegExp(r'logoHeight:\s*([0-9.]+)')
          .allMatches(model)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(heights, isNotEmpty);
      expect(heights.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(26),
          reason: 'logoHeight 最大值超过 26 时需同步调大预热宽度');
    });
  });
}

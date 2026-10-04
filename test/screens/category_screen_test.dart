import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

import '../helpers/test_fakes.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  FakeEmbyService? emby,
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyServiceProvider.overrideWith((ref) => emby ?? FakeEmbyService()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CategoryScreen(libraryId: 'lib1', collectionType: 'movies'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分类网格卡片：海报完整 2:3、标题在海报下方、带评分与集数角标', (tester) async {
    await _pumpScreen(
      tester,
      emby: FakeEmbyService(
        items: [
          MediaItem(
            id: 'm1',
            name: '测试影片',
            type: 'Movie',
            posterUrl: '',
            year: '2026',
            communityRating: 8.5,
            indexNumber: 12,
          ),
          MediaItem(
            id: 'm2',
            name: '另一部',
            type: 'Movie',
            posterUrl: '',
          ),
        ],
      ),
    );

    // 不再套黑底 Card
    expect(find.byType(Card), findsNothing);

    final card = find.byKey(const ValueKey('posterCard_m1'));
    expect(card, findsOneWidget);

    final poster = tester.getRect(
      find.descendant(of: card, matching: find.byType(EmbyImage)),
    );
    final title = tester.getRect(
      find.descendant(of: card, matching: find.text('测试影片')),
    );
    final year = tester.getRect(
      find.descendant(of: card, matching: find.text('2026')),
    );

    expect(poster.height, closeTo(poster.width * 1.5, 1.0));
    expect(title.top, greaterThanOrEqualTo(poster.bottom));
    expect(year.top, greaterThanOrEqualTo(title.bottom));

    expect(
      find.descendant(of: card, matching: find.text('8.5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('12')),
      findsOneWidget,
    );
  });

  group('gridColumns（分类页每行海报数）', () {
    test('自动：TV 每行基准 120 逻辑px（960 宽 → 8 列，原为 5）', () {
      expect(CategoryScreen.gridColumns(width: 960, tvMode: true), 8);
      expect(CategoryScreen.gridColumns(width: 853, tvMode: true), 7);
      expect(CategoryScreen.gridColumns(width: 1280, tvMode: true), 10);
      expect(CategoryScreen.gridColumns(width: 1920, tvMode: true), 14,
          reason: '超宽封顶 14 列');
    });

    test('自动：非 TV 分支与旧逻辑一致（宽屏 /180，窄屏 4）', () {
      expect(CategoryScreen.gridColumns(width: 960, tvMode: false), 5);
      expect(CategoryScreen.gridColumns(width: 1800, tvMode: false), 10);
      expect(CategoryScreen.gridColumns(width: 601, tvMode: false), 3);
      expect(CategoryScreen.gridColumns(width: 500, tvMode: false), 4);
      expect(CategoryScreen.gridColumns(width: 380, tvMode: false), 4);
      expect(CategoryScreen.gridColumns(width: 9600, tvMode: false), 12,
          reason: '非 TV 宽屏封顶 12 列');
    });

    test('指定列数优先，屏幕放不下自动压回（每列 ≥80 逻辑px）', () {
      expect(
        CategoryScreen.gridColumns(width: 960, tvMode: true, columns: 10),
        10,
      );
      expect(
        CategoryScreen.gridColumns(width: 960, tvMode: false, columns: 12),
        12,
      );
      // 380 宽最多 4 列 → 指定 10 压回 4
      expect(
        CategoryScreen.gridColumns(width: 380, tvMode: false, columns: 10),
        4,
        reason: '每列不低于 80 逻辑px',
      );
      // 960 宽上限 12 → 指定 14 压回 12；TV 上限 14 → 指定 14 保留
      expect(
        CategoryScreen.gridColumns(width: 960, tvMode: false, columns: 14),
        12,
      );
      expect(
        CategoryScreen.gridColumns(width: 1920, tvMode: true, columns: 14),
        14,
      );
      // 窄屏自动 4 不受指定影响之外，指定 1 列也允许（超宽海报）
      expect(
        CategoryScreen.gridColumns(width: 380, tvMode: false, columns: 1),
        1,
      );
    });
  });

  group('背景跟随主题色', () {
    BoxDecoration _backgroundDecoration(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(
        find.byKey(const Key('categoryBackground')),
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('未设主题色：整页保持应用底色（现状零变化）', (tester) async {
      await _pumpScreen(tester);
      final gradient = _backgroundDecoration(tester).gradient!;
      final base = Theme.of(tester.element(find.byType(CategoryScreen)))
          .scaffoldBackgroundColor;

      expect(gradient.colors, everyElement(base),
          reason: 'accent=null 时 pageGradient 全段 base');
    });

    testWidgets('设主题色：渐变首色 = darkenForPage(主题色)', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(themeColor: 0xFF6366F1),
      );
      final gradient = _backgroundDecoration(tester).gradient!;

      expect(
        gradient.colors.first,
        PosterPalette.darkenForPage(const Color(0xFF6366F1)),
        reason: '三段渐变顶部为主色调暗色',
      );
      expect(gradient.colors.first, isNot(gradient.colors.last),
          reason: '渐变应有主色→底色过渡');
    });
  });
}

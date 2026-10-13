import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/category_filter.dart';
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
  testWidgets('最近添加排序：SortBy=DateLastContentAdded 下传服务端', (tester) async {
    final emby = FakeEmbyService(items: [
      MediaItem(id: 'm1', name: '剧', type: 'Series', posterUrl: ''),
    ]);
    await _pumpScreen(tester, emby: emby);

    expect(SortOption.dateDesc.label, '最近添加');
    expect(SortOption.dateDesc.sortOrder, 'Descending');
    expect(
      SortOption.dateDesc.sortBy,
      'DateLastContentAdded',
      reason: 'DateCreated 是系列首次入库时间、有新集也不变——更新过的'
          '剧集排不到前面；DateLastContentAdded 随子项入库更新',
    );
    expect(emby.lastGetItemsSortBy, 'DateLastContentAdded',
        reason: '默认排序应实际下传服务端');
    expect(emby.lastGetItemsSortOrder, 'Descending');
  });

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

  group('筛选面板', () {
    /// 打开面板并选择「未播放」+ 类型「动作」后确认。
    Future<void> _applyFilter(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('categoryFilterButton')));
      await tester.pumpAndSettle();

      // 播放状态 → 未播放
      await tester.tap(find.byType(DropdownButton<WatchStatusFilter>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未播放').last);
      await tester.pumpAndSettle();

      // 类型 → + → 勾选「动作」→ 确认
      await tester.tap(find.byKey(const Key('filterAdd_类型_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filterPick_类型_动作')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filterPick_类型_confirm')));
      await tester.pumpAndSettle();

      // 应用筛选
      await tester.tap(find.byKey(const Key('filterConfirmButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('筛选确认后 filters/genres 下传服务端并重载分页', (tester) async {
      final emby = FakeEmbyService(
        items: [MediaItem(id: 'm1', name: '片', type: 'Movie', posterUrl: '')],
        filterOptions: const MediaFilterOptions(
          genres: ['动作', '科幻'],
          years: [2024, 2023],
          ratings: ['R'],
        ),
      );
      await _pumpScreen(tester, emby: emby);
      expect(emby.lastGetItemsFilters, isNull);

      await _applyFilter(tester);

      expect(emby.lastGetItemsFilters, 'IsUnplayed');
      expect(emby.lastGetItemsGenres, '动作');
      expect(emby.lastFilterOptionsParentId, 'lib1',
          reason: '可选项限定当前分类库');
      expect(emby.lastFilterOptionsIncludeItemTypes, 'Movie',
          reason: '电影库可选项按 Movie 限定');
      expect(
        tester.widget<IconButton>(
          find.byKey(const Key('categoryFilterButton')),
      ).icon,
        isA<Icon>().having((i) => i.color, 'color', isNotNull),
        reason: '筛选激活时按钮着色',
      );
    });

    testWidgets('可选项按库懒加载：再次打开不重复请求', (tester) async {
      var fetchCount = 0;
      final emby = FakeEmbyService(
        items: const [],
        filterOptions: const MediaFilterOptions(years: [2024]),
      );
      // 计数包装：getFilterOptions 每次调用 +1
      final counting = _CountingEmbyService(emby, () => fetchCount++);
      await _pumpScreen(tester, emby: counting);

      await tester.tap(find.byKey(const Key('categoryFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filterCancelButton')));
      await tester.pumpAndSettle();
      expect(fetchCount, 1);

      await tester.tap(find.byKey(const Key('categoryFilterButton')));
      await tester.pumpAndSettle();
      expect(fetchCount, 1, reason: '同一类型范围内只请求一次可选项');
      await tester.tap(find.byKey(const Key('filterCancelButton')));
      await tester.pumpAndSettle();
    });

    testWidgets('筛选后无结果显示「筛选无匹配项」', (tester) async {
      final emby = FakeEmbyService(
        items: const [],
        filterOptions: const MediaFilterOptions(years: [2024]),
      );
      await _pumpScreen(tester, emby: emby);
      expect(find.text('暂无内容'), findsOneWidget);

      await tester.tap(find.byKey(const Key('categoryFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<WatchStatusFilter>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已播放').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filterConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.text('筛选无匹配项'), findsOneWidget);
      expect(find.text('暂无内容'), findsNothing);
    });
  });
}

/// 计数包装：统计 getFilterOptions 调用次数，其余转发给内嵌 fake。
class _CountingEmbyService extends FakeEmbyService {
  _CountingEmbyService(this.inner, this.onCall);

  final FakeEmbyService inner;
  final void Function() onCall;

  @override
  Future<MediaFilterOptions> getFilterOptions({
    String? parentId,
    String? includeItemTypes,
  }) async {
    onCall();
    return inner.getFilterOptions(
      parentId: parentId,
      includeItemTypes: includeItemTypes,
    );
  }
}

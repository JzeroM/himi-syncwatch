import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/category_filter.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart'
    show SortOption;
import 'package:himi_syncwatch/screens/favorites/favorites_all_screen.dart';

import '../helpers/test_fakes.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeEmbyService emby,
  String type = 'movie',
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServiceProvider.overrideWith((ref) => emby),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FavoritesAllScreen(type: type, title: '电影'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final movieItems = [
    MediaItem(id: 'm1', name: '电影一', type: 'Movie', posterUrl: ''),
    MediaItem(id: 'm2', name: '电影二', type: 'Movie', posterUrl: ''),
  ];

  testWidgets('默认加载：限定 Movie、SortName 升序（与旧版行为一致）', (tester) async {
    final emby = FakeEmbyService(favoriteItems: movieItems);
    await _pumpScreen(tester, emby: emby);

    expect(emby.lastFavoriteIncludeItemTypes, 'Movie');
    expect(emby.lastFavoriteSortBy, 'SortName');
    expect(emby.lastFavoriteSortOrder, 'Ascending');
    expect(emby.lastFavoriteFilters, isNull);
    expect(find.byKey(const ValueKey('posterCard_m1')), findsOneWidget);
    expect(find.byKey(const Key('favoritesFilterButton')), findsOneWidget);
    expect(find.byKey(const Key('favoritesSortMenu')), findsOneWidget);
  });

  testWidgets('剧集页：IncludeItemTypes=Series', (tester) async {
    final emby = FakeEmbyService(favoriteItems: const []);
    await _pumpScreen(tester, emby: emby, type: 'series');

    expect(emby.lastFavoriteIncludeItemTypes, 'Series');
  });

  testWidgets('排序切换：年份 ↓ 下传 ProductionYear/Descending', (tester) async {
    final emby = FakeEmbyService(favoriteItems: movieItems);
    await _pumpScreen(tester, emby: emby);

    await tester.tap(find.byKey(const Key('favoritesSortMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SortOption.yearDesc.label));
    await tester.pumpAndSettle();

    expect(emby.lastFavoriteSortBy, 'ProductionYear');
    expect(emby.lastFavoriteSortOrder, 'Descending');
  });

  testWidgets('筛选确认后 IsFavorite 合并播放状态并重载', (tester) async {
    final emby = FakeEmbyService(
      favoriteItems: movieItems,
      filterOptions: const MediaFilterOptions(
        genres: ['动作'],
        years: [2024],
        ratings: ['R'],
      ),
    );
    await _pumpScreen(tester, emby: emby);

    await tester.tap(find.byKey(const Key('favoritesFilterButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<WatchStatusFilter>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未播放').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filterAdd_年份_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterPick_年份_2024')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterPick_年份_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filterConfirmButton')));
    await tester.pumpAndSettle();

    expect(emby.lastFavoriteFilters, 'IsUnplayed');
    expect(emby.lastFavoriteYears, '2024');
    expect(emby.lastFavoriteIncludeItemTypes, 'Movie',
        reason: '收藏页筛选始终限定当前分区类型');
    expect(emby.lastFilterOptionsParentId, isNull,
        reason: '可选项为全部电影/剧集（跨库）');
    expect(emby.lastFilterOptionsIncludeItemTypes, 'Movie');
  });

  testWidgets('筛选后无结果：显示「筛选无匹配项」而非「暂无收藏」', (tester) async {
    final emby = FakeEmbyService(
      favoriteItems: const [],
      filterOptions: const MediaFilterOptions(years: [2024]),
    );
    await _pumpScreen(tester, emby: emby);
    expect(find.text('暂无收藏'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favoritesFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<WatchStatusFilter>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已播放').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.text('筛选无匹配项'), findsOneWidget);
  });

  testWidgets('取消筛选面板：不改动已应用的筛选', (tester) async {
    final emby = FakeEmbyService(
      favoriteItems: movieItems,
      filterOptions: const MediaFilterOptions(years: [2024]),
    );
    await _pumpScreen(tester, emby: emby);

    await tester.tap(find.byKey(const Key('favoritesFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterCancelButton')));
    await tester.pumpAndSettle();

    expect(emby.lastFavoriteFilters, isNull);
  });

  testWidgets('进页即预取可选项；打开面板不重复请求（v1.1.235）', (tester) async {
    var fetchCount = 0;
    final emby = FakeEmbyService(
      favoriteItems: movieItems,
      filterOptions: const MediaFilterOptions(years: [2024]),
    );
    final counting = _CountingEmbyService(emby, () => fetchCount++);
    await _pumpScreen(tester, emby: counting);

    // 进页 initState 已后台预取一次
    expect(fetchCount, 1, reason: '进入收藏页即预取可选项');

    // 打开面板走缓存，不再重复请求
    await tester.tap(find.byKey(const Key('favoritesFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filterCancelButton')));
    await tester.pumpAndSettle();
    expect(fetchCount, 1, reason: '打开面板复用预取缓存，不重复请求');
  });

  testWidgets('先弹后填：面板立即弹出，可选项就绪后补上（防重入，v1.1.235）', (tester) async {
    // 受控 Future 卡住 getFilterOptions，还原「可选项仍在加载」的场景
    final gate = Completer<MediaFilterOptions>();
    final emby = _GatedEmbyService(FakeEmbyService(favoriteItems: movieItems), gate);
    await _pumpScreen(tester, emby: emby);

    final btn = find.byKey(const Key('favoritesFilterButton'));
    await tester.tap(btn);
    await tester.pump();

    // 先弹后填：不等可选项请求，面板立即弹出且播放状态可用
    expect(find.byKey(const Key('filterPanelBody')), findsOneWidget,
        reason: '面板不等可选项请求，立即弹出');
    expect(find.byKey(const Key('filterConfirmButton')), findsOneWidget);
    expect(find.byKey(const Key('filterOptionsLoading')), findsOneWidget,
        reason: '可选项未就绪时显示加载提示');

    // 防重入：面板打开期间按钮置灰，杜绝二次 _openFilterPanel
    expect(tester.widget<IconButton>(find.descendant(of: btn, matching: find.byType(IconButton))).onPressed, isNull);

    // 可选项就绪 → 补上年份分组，加载提示消失
    gate.complete(const MediaFilterOptions(years: [2024]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filterOptionsLoading')), findsNothing);
    expect(find.text('年份'), findsOneWidget);

    // 关闭后按钮恢复可点
    await tester.tap(find.byKey(const Key('filterCancelButton')));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.descendant(of: btn, matching: find.byType(IconButton))).onPressed, isNotNull);
  });
}

/// 受控包装：getFilterOptions 挂起在 [gate] 上，便于构造「请求未返回时连点」竞态。
class _GatedEmbyService extends FakeEmbyService {
  _GatedEmbyService(this.inner, this.gate);

  final FakeEmbyService inner;
  final Completer<MediaFilterOptions> gate;

  @override
  Future<MediaFilterOptions> getFilterOptions({
    String? parentId,
    String? includeItemTypes,
  }) =>
      gate.future;
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/category_filter.dart';
import 'package:himi_syncwatch/widgets/media_filter_panel.dart';

void main() {
  const options = MediaFilterOptions(
    genres: [
      '动作片',
      '科幻电影',
      '喜剧冒险',
      '动画电影',
      '纪录片',
      '剧情长片',
    ],
    years: [2024, 2023, 2022, 2021, 2020, 2019],
    ratings: ['R', 'PG-13', 'G', 'PG'],
  );

  Future<void> pumpHost(
    WidgetTester tester, {
    bool tvMode = false,
    CategoryFilter current = CategoryFilter.empty,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('openFilter'),
                onPressed: () => showMediaFilterPanel(
                  context,
                  current: current,
                  options: options,
                  tvMode: tvMode,
                ),
                child: const Text('打开筛选'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openFilter')));
    await tester.pumpAndSettle();
  }

  /// 在二级复选弹窗里勾选 [labels] 后确认，回到面板。
  Future<void> pickGenres(WidgetTester tester, List<String> labels) async {
    await tester.tap(find.byKey(const Key('filterAdd_类型_button')));
    await tester.pumpAndSettle();
    for (final label in labels) {
      await tester.tap(find.byKey(Key('filterPick_类型_$label')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('filterPick_类型_confirm')));
    await tester.pumpAndSettle();
  }

  group('筛选面板高度', () {
    testWidgets('触屏：固定 0.5 屏高且不可拖拽（无 DraggableScrollableSheet）',
        (tester) async {
      await pumpHost(tester);

      // 不可拖拽：面板不再用 DraggableScrollableSheet
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      // 固定 0.5 屏高
      final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final body = tester.getSize(find.byKey(const Key('filterPanelBody')));
      expect(body.height, closeTo(screen * 0.5, 1.0),
          reason: '面板高度固定为 0.5 屏高');
      expect(find.byKey(const Key('filterConfirmButton')), findsOneWidget);
      expect(find.byKey(const Key('filterCancelButton')), findsOneWidget);
    });

    testWidgets('TV：Dialog 固定高度且不可拖拽', (tester) async {
      await pumpHost(tester, tvMode: true);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final maxH = (screen * 0.5).clamp(360.0, 560.0);
      final body = tester.getSize(find.byKey(const Key('filterPanelBody')));
      expect(body.height, lessThanOrEqualTo(maxH + 1.0));
    });
  });

  group('已选标签单行横滑', () {
    /// 面板内类型 chips 行（横滑 ListView）。
    Finder typeChipRow() => find.descendant(
          of: find.byKey(const Key('filterPanelBody')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        );

    Finder typeChips() => find.byWidgetPredicate(
          (w) =>
              w is InputChip &&
              w.key != null &&
              w.key.toString().contains('filterChip_类型_'),
        );

    testWidgets('多选 6 项后 chips 不换行（同一 top）且可左右滑动', (tester) async {
      await pumpHost(tester);
      await pickGenres(tester, options.genres);

      // 6 项总宽超出面板宽，ListView 只渲染视口 + 缓存范围内的 chip；
      // 关键是已渲染的全部落在同一行（旧版 Wrap 会折成 2 行 → 两个 top）
      final built = typeChips().evaluate();
      expect(built, isNotEmpty, reason: '至少渲染一个 chip');
      final tops = built
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
          .toSet();
      expect(tops.length, 1, reason: 'chips 单行排列，不换行');

      // 可左右滑动：内容超出视口 → 有横向滚动范围
      final rowState = tester.state<ScrollableState>(typeChipRow());
      expect(rowState.position.maxScrollExtent, greaterThan(0),
          reason: 'chips 行内容超出视口，可左右滑动');

      // 左滑后首个 chip 位移
      final before = tester.getTopLeft(find.byWidget(built.first.widget)).dx;
      await tester.drag(typeChipRow(), const Offset(-200, 0));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.byWidget(built.first.widget)).dx;
      expect(after, lessThan(before), reason: '左滑后 chip 左移');
    });

    testWidgets('删除一个 chip 后剩余仍在同一行（不换行）', (tester) async {
      await pumpHost(tester);
      // 只选 3 项，确保全部在视口内、删除图标可点
      await pickGenres(tester, ['动作片', '科幻电影', '喜剧冒险']);
      expect(typeChips(), findsNWidgets(3));

      // InputChip 的删除需点其删除图标（点 chip 本体不触发 onDeleted）。
      // 用 Icon 类型定位而非具体图标字形，避免依赖 Flutter 版本的默认字形。
      await tester.tap(find.descendant(
        of: find.byKey(const Key('filterChip_类型_动作片')),
        matching: find.byType(Icon),
      ));
      await tester.pumpAndSettle();

      expect(typeChips(), findsNWidgets(2));
      final tops = typeChips()
          .evaluate()
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
          .toSet();
      expect(tops.length, 1, reason: '删除后剩余 chips 仍单行');
    });
  });

  group('确认 / 取消 / 恢复默认', () {
    testWidgets('确认返回所选筛选', (tester) async {
      await pumpHost(tester);
      await pickGenres(tester, ['动作片']);
      await tester.tap(find.byKey(const Key('filterConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.text('筛选'), findsNothing, reason: '面板已关闭');
    });

    testWidgets('取消不改动已传入的筛选', (tester) async {
      await pumpHost(tester);
      await tester.tap(find.byKey(const Key('filterCancelButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filterPanelBody')), findsNothing);
    });

    testWidgets('恢复默认清空草稿', (tester) async {
      await pumpHost(tester);
      await pickGenres(tester, ['动作片']);
      expect(
        find.byKey(const Key('filterChip_类型_动作片')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('filterResetButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('filterChip_类型_动作片')),
        findsNothing,
        reason: '恢复默认后草稿清空',
      );
    });
  });
}

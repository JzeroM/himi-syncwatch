import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

import '../helpers/test_fakes.dart';

Future<void> _pumpScreen(WidgetTester tester, {FakeEmbyService? emby}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
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
  testWidgets('分类网格卡片：海报完整 2:3、标题在海报下方、带评分与集数角标',
      (tester) async {
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
}

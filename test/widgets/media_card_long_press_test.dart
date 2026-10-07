import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/continue_watching_card.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

import '../helpers/test_fakes.dart';

Widget _host(Widget child) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('PosterCard 长按回调携带卡片矩形', (tester) async {
    Rect? got;
    final item = MediaItem(id: 'm1', name: '测试影片', type: 'Movie');
    await tester.pumpWidget(_host(
      PosterCard(
        item: item,
        width: 120,
        onTap: () {},
        onLongPress: (r) => got = r,
      ),
    ));
    await tester.longPress(find.byType(PosterCard));
    await tester.pump();
    expect(got, isNotNull);
    expect(got!.width, greaterThan(0));
    expect(got!.height, greaterThan(0));
  });

  testWidgets('ContinueWatchingCard 长按回调携带卡片矩形', (tester) async {
    Rect? got;
    final item = MediaItem(
      id: 'e1',
      name: '第1集',
      type: 'Episode',
      seriesName: '某剧',
      parentIndexNumber: 1,
      indexNumber: 1,
      playbackPositionMs: 1000,
    );
    await tester.pumpWidget(_host(
      ContinueWatchingCard(
        item: item,
        width: 200,
        onTap: () {},
        onLongPress: (r) => got = r,
      ),
    ));
    await tester.longPress(find.byType(ContinueWatchingCard));
    await tester.pump();
    expect(got, isNotNull);
    expect(got!.width, greaterThan(0));
  });

  testWidgets('未提供 onLongPress 时卡片不崩溃', (tester) async {
    final item = MediaItem(id: 'm2', name: '影片', type: 'Movie');
    await tester.pumpWidget(_host(
      PosterCard(item: item, width: 120, onTap: () {}),
    ));
    await tester.longPress(find.byType(PosterCard));
    await tester.pump();
    expect(find.byType(PosterCard), findsOneWidget);
  });
}

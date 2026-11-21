import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/continue_watching_card.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

import '../helpers/test_fakes.dart';

void main() {
  const backdrop = 'https://e.test/Items/m1/Images/Backdrop?maxHeight=400&tag=b';
  const poster = 'https://e.test/Items/m1/Images/Primary?maxHeight=400&tag=p';

  Widget wrap(MediaItem item) => UncontrolledProviderScope(
        container: ProviderContainer(
          overrides: [
            settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
          ],
        ),
        child: MaterialApp(
          home: Scaffold(
            body: ContinueWatchingCard(item: item, width: 200),
          ),
        ),
      );

  testWidgets('图源 = 背景图优先（698 N8-E）：16:9 横卡满框不裁切', (tester) async {
    await tester.pumpWidget(wrap(MediaItem(
      id: 'm1',
      name: '影片',
      type: 'Movie',
      posterUrl: poster,
      backdropUrl: backdrop,
    )));
    await tester.pump();

    final img = tester.widget<EmbyImage>(find.byType(EmbyImage).first);
    expect(img.url, contains('Backdrop'),
        reason: '继续观看横卡用对应资源的背景图（海报兜底）');
    expect(img.fit, BoxFit.cover);
  });

  testWidgets('无背景图 → 封面兜底', (tester) async {
    await tester.pumpWidget(wrap(MediaItem(
      id: 'm1',
      name: '影片',
      type: 'Movie',
      posterUrl: poster,
    )));
    await tester.pump();

    final img = tester.widget<EmbyImage>(find.byType(EmbyImage).first);
    expect(img.url, contains('Primary'), reason: '无背景图用封面兜底');
  });

  testWidgets('card 槽位取图（w540 档同宽解码，698 N8-E）', (tester) async {
    await tester.pumpWidget(wrap(MediaItem(
      id: 'm1',
      name: '影片',
      type: 'Movie',
      backdropUrl: backdrop,
    )));
    await tester.pump();

    final img = tester.widget<EmbyImage>(find.byType(EmbyImage).first);
    expect(img.cacheWidth, isNotNull);
    expect(img.cacheWidth, lessThanOrEqualTo(540), reason: 'card 档上限 540');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

import '../helpers/test_fakes.dart';

const _posterUrl = 'https://emby.test/Items/m1/Images/Primary';

final _item = MediaItem(
  id: 'm1',
  name: '测试影片',
  type: 'Movie',
  posterUrl: _posterUrl,
  overview: '这是一段测试简介。',
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  Color? accent,
  FakeEmbyService? emby,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServiceProvider
          .overrideWith((ref) => emby ?? FakeEmbyService(item: _item)),
      posterColorProvider(_posterUrl).overrideWith((ref) async => accent),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const DetailScreen(itemId: 'm1'),
      ),
    ),
  );
  // 图片占位转圈动画不会 settle，改为固定帧推进：
  // 首帧处理加载微任务，再推进超过 500ms 的渐变过渡动画。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

LinearGradient _pageGradient(WidgetTester tester) {
  final container =
      tester.widget<AnimatedContainer>(find.byKey(const Key('detailBackground')));
  final decoration = container.decoration! as BoxDecoration;
  return decoration.gradient! as LinearGradient;
}

void main() {
  testWidgets('取色成功时背景为海报主色垂直渐变', (tester) async {
    const accent = Color(0xFF3366AA);
    await _pumpDetail(tester, accent: accent);

    final gradient = _pageGradient(tester);
    expect(gradient.colors.first, accent);
    expect(gradient.colors.last, ThemeData.dark().scaffoldBackgroundColor);
    expect(gradient.colors.length, 3);
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('取色失败时背景保持页面底色', (tester) async {
    await _pumpDetail(tester, accent: null);

    final gradient = _pageGradient(tester);
    final base = ThemeData.dark().scaffoldBackgroundColor;
    expect(gradient.colors.toSet(), {base});
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('跨服务器详情按 serverId 使用来源服务器的服务', (tester) async {
    final target = EmbyServerConfig(
      id: 'srv-b',
      serverUrl: 'https://b.example.com',
      serverName: '服务器B',
      serverId: 'srv-b',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );
    EmbyServerConfig? used;
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        // 当前激活服务器返回 null：若误用当前服务会加载失败
        embyServiceProvider.overrideWith((ref) => FakeEmbyService(item: null)),
        embyServiceFactoryProvider.overrideWithValue((cfg) {
          used = cfg;
          return FakeEmbyService(item: _item);
        }),
        posterColorProvider(_posterUrl).overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(embyServerListProvider.notifier)
        .setList([target]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const DetailScreen(itemId: 'm1', serverId: 'srv-b'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));

    expect(used?.id, 'srv-b');
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('相似推荐卡片：无黑底 Card、标题在海报下方、评分与集数角标', (tester) async {
    await _pumpDetail(
      tester,
      emby: FakeEmbyService(
        item: _item,
        similar: [
          MediaItem(
            id: 's1',
            name: '相似影片',
            type: 'Movie',
            posterUrl: '',
            year: '2024',
            communityRating: 7.2,
            indexNumber: 5,
          ),
        ],
      ),
    );

    expect(find.text('相似推荐'), findsOneWidget);
    expect(find.byType(Card), findsNothing);

    final card = find.byKey(const ValueKey('posterCard_s1'));
    expect(card, findsOneWidget);

    final poster = tester.getRect(
      find.descendant(of: card, matching: find.byType(EmbyImage)),
    );
    final title = tester.getRect(
      find.descendant(of: card, matching: find.text('相似影片')),
    );
    expect(title.top, greaterThanOrEqualTo(poster.bottom));
    expect(poster.height, closeTo(poster.width * 1.5, 0.5));

    expect(
      find.descendant(of: card, matching: find.text('7.2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('5')),
      findsOneWidget,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/detail/media_details_section.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

import '../helpers/test_fakes.dart';

Widget _host(Widget child) => ProviderScope(
      overrides: [
        settingsProvider
            .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
      ],
      child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  group('externalLinksFor', () {
    test('providerIds 拼出 IMDb / TMDb(剧集 tv) / TVDB', () {
      final item = MediaItem(
        id: 's1',
        name: '剧',
        type: 'Series',
        providerIds: {'Imdb': 'tt1', 'Tmdb': '9', 'Tvdb': '8'},
      );
      final links = MediaDetailsSection.externalLinksFor(item);
      expect(links.map((l) => l.name),
          containsAll(['IMDb', 'TheMovieDb', 'TheTVDB']));
      expect(
        links.firstWhere((l) => l.name == 'TheMovieDb').url,
        'https://www.themoviedb.org/tv/9',
      );
    });

    test('ExternalUrls 优先且按名去重', () {
      final item = MediaItem(
        id: 'm1',
        name: '电影',
        type: 'Movie',
        externalUrls: const [
          ExternalUrl(name: 'IMDb', url: 'https://www.imdb.com/title/tt1/')
        ],
        providerIds: {'Imdb': 'tt1'},
      );
      final links = MediaDetailsSection.externalLinksFor(item);
      expect(links.where((l) => l.name == 'IMDb').length, 1);
      expect(links.first.url, 'https://www.imdb.com/title/tt1/');
    });

    test('无外链信息 → 空', () {
      expect(
        MediaDetailsSection.externalLinksFor(
            MediaItem(id: 'm1', name: '电影', type: 'Movie')),
        isEmpty,
      );
    });
  });

  test('formatBitrate：Mbps / kbps', () {
    expect(MediaDetailsSection.formatBitrate(8000000), '8.0 Mbps');
    expect(MediaDetailsSection.formatBitrate(128000), '128 kbps');
    expect(MediaDetailsSection.formatBitrate(null), '-');
  });

  test('aspectRatio 约分', () {
    expect(MediaDetailsSection.aspectRatio(1920, 1080), '16:9');
    expect(MediaDetailsSection.aspectRatio(null, 1080), '-');
  });

  testWidgets('渲染外部链接 / 工作室 / 媒体信息 / 视频 / 音频', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '电影',
      type: 'Movie',
      path: '/media/x.mkv',
      studios: const ['Netflix'],
      providerIds: const {'Imdb': 'tt1'},
      mediaStreams: [
        MediaStream(
          type: 'Video',
          codec: 'hevc',
          width: 1920,
          height: 1080,
          profile: 'Main 10',
          bitDepth: 10,
          pixelFormat: 'yuv420p10le',
          frameRate: 23.976025,
          isInterlaced: false,
          videoRange: 'HDR',
        ),
        MediaStream(
          type: 'Audio',
          codec: 'eac3',
          channels: 2,
          channelLayout: 'stereo',
          sampleRate: 48000,
          bitRate: 128000,
          profile: 'LC',
        ),
      ],
    );

    expect(MediaDetailsSection.hasContent(item), isTrue);
    await tester.pumpWidget(_host(MediaDetailsSection(item: item)));
    await tester.pump();

    expect(find.text('外部链接'), findsOneWidget);
    expect(find.text('工作室'), findsOneWidget);
    expect(find.text('媒体信息'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  test('hasContent：无任何信息 → false', () {
    expect(
      MediaDetailsSection.hasContent(
          MediaItem(id: 'm1', name: '电影', type: 'Movie')),
      isFalse,
    );
  });

  test('hasContent：仅有相似推荐也算有内容', () {
    expect(
      MediaDetailsSection.hasContent(
        MediaItem(id: 'm1', name: '电影', type: 'Movie'),
        similarItems: [MediaItem(id: 's1', name: '相似', type: 'Movie')],
      ),
      isTrue,
    );
  });

  testWidgets('相似推荐渲染在外部链接之上；视频/音频横滑；胶囊/卡片为玻璃', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '电影',
      type: 'Movie',
      studios: const ['Netflix'],
      providerIds: const {'Imdb': 'tt1'},
      mediaStreams: [
        MediaStream(type: 'Video', codec: 'hevc', width: 1920, height: 1080),
        MediaStream(type: 'Audio', codec: 'eac3', channels: 2),
      ],
    );
    final similar = [MediaItem(id: 's1', name: '相似', type: 'Movie')];

    await tester.pumpWidget(
      _host(MediaDetailsSection(item: item, similarItems: similar)),
    );
    await tester.pump();

    final similarY = tester.getTopLeft(find.text('相似推荐')).dy;
    final linksY = tester.getTopLeft(find.text('外部链接')).dy;
    expect(similarY, lessThan(linksY), reason: '相似推荐在外部链接之上');

    // 视频/音频卡横向可滑动
    final horizontals = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    expect(horizontals, isNotEmpty, reason: '视频/音频面板横向滚动');

    // 玻璃化：胶囊与卡片使用 GlassContainer
    expect(find.byType(GlassContainer), findsWidgets);
    expect(find.byType(Chip), findsNothing, reason: '工作室已改玻璃胶囊');
  });

  testWidgets('面板高度自适应：最长卡不裁切且各卡等高', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '电影',
      type: 'Movie',
      mediaStreams: [
        MediaStream(
          type: 'Video',
          codec: 'hevc',
          width: 1920,
          height: 1080,
          profile: 'Main 10',
          level: 150,
          bitDepth: 10,
          pixelFormat: 'yuv420p10le',
          refFrames: 1,
          frameRate: 23.976,
          isInterlaced: false,
          videoRange: 'HDR',
        ),
        MediaStream(
          type: 'Audio',
          codec: 'eac3',
          channels: 2,
          channelLayout: 'stereo',
          sampleRate: 48000,
          bitRate: 128000,
          profile: 'LC',
        ),
      ],
    );
    await tester.pumpWidget(_host(MediaDetailsSection(item: item)));
    await tester.pump();

    // 视频最长卡的最后一行（参考帧）与音频卡最后一行（默认）均未被裁
    // （固定高度不足会触发布局 overflow 异常使测试失败）
    expect(find.text('参考帧'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);

    // 两张卡等高（同一高度约束）
    final cards =
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 300);
    expect(cards, findsNWidgets(2));
    expect(
      tester.getSize(cards.at(0)).height,
      tester.getSize(cards.at(1)).height,
      reason: '所有卡与最长卡等高对齐',
    );
  });
}

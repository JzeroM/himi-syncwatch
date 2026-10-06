import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/screens/detail/media_details_section.dart';

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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: MediaDetailsSection(item: item)),
      ),
    ));
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
}

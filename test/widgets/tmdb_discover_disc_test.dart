import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/widgets/tmdb_discover_disc.dart';

final _server = EmbyServerConfig(
  id: 's1',
  serverUrl: 'https://s1',
  serverName: '服务器A',
  serverId: 'srv-s1',
  username: 'user',
  accessToken: 'token',
  userId: 'u1',
);

TmdbAvailability _entry(int id) => TmdbAvailability(
      tmdb: TmdbItem(
        id: id,
        type: TmdbMediaType.movie,
        title: '影片$id',
      ),
      item: MediaItem(id: '$id', name: '影片$id', type: 'Movie'),
      server: _server,
    );

TmdbDiscSectionData _section(String key, String title, int start) =>
    TmdbDiscSectionData(
      key: key,
      title: title,
      items: [for (var i = 0; i < 3; i++) _entry(start + i)],
    );

List<TmdbDiscSectionData> _sections(int count) => [
      for (var i = 0; i < count; i++)
        _section('section_$i', '分区$i', 100 + i * 10),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required List<TmdbDiscSectionData> sections,
  bool tvMode = false,
  FocusNode? focusNode,
  required List<String> opened,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: TmdbDiscCarousel(
          sections: sections,
          imageBase: 'https://image.tmdb.org/t/p',
          tvMode: tvMode,
          focusNode: focusNode,
          onOpenSection: (section) => opened.add(section.key),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('视野只构建左中右三个分区', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    expect(find.text('分区4'), findsOneWidget);
    expect(find.text('分区0'), findsOneWidget);
    expect(find.text('分区1'), findsOneWidget);
    expect(find.text('分区2'), findsNothing);
    expect(find.text('分区3'), findsNothing);
    expect(find.byKey(const ValueKey('tmdbDiscEdgeFade')), findsNothing);
  });

  testWidgets('组件高度收紧且三块面板内容完整保留', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final size = tester.getSize(find.byType(TmdbDiscCarousel));
    expect(size.height, closeTo(207.5, 0.5));
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    expect(find.text('查看全部 ›'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('tmdbDiscEdgeFade')), findsNothing);
  });

  testWidgets('高亮面板标题居中', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final titleCenter = tester.getCenter(find.text('分区0'));
    expect(titleCenter.dx, closeTo(250, 15));
  });

  testWidgets('分区数量增加后仍然只构建三个分区', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(7), opened: opened);

    expect(find.text('分区6'), findsOneWidget);
    expect(find.text('分区0'), findsOneWidget);
    expect(find.text('分区1'), findsOneWidget);
    expect(find.text('分区2'), findsNothing);
    expect(find.text('分区5'), findsNothing);
  });

  testWidgets('左滑吸附到下一分区', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    await tester.drag(
      find.byType(TmdbDiscCarousel),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('分区0'), findsOneWidget);
    expect(find.text('分区1'), findsOneWidget);
    expect(find.text('分区2'), findsOneWidget);
    expect(find.text('分区4'), findsNothing);
  });

  testWidgets('TV 左右键切换、Enter 打开当前分区', (tester) async {
    final opened = <String>[];
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pump(
      tester,
      sections: _sections(5),
      tvMode: true,
      focusNode: focusNode,
      opened: opened,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('分区2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['section_1']);
  });

  testWidgets('点击海报打开对应栏目页', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    await tester.tap(
      find.byKey(
        const ValueKey('tmdbDiscPoster_section_0_movie:101'),
      ),
    );
    await tester.pump();

    expect(opened, ['section_0']);
  });

  test('每个分区随机 3 张，同种子稳定，不同种子变化', () {
    final items = [for (var i = 0; i < 8; i++) _entry(i)];

    final first = pickTmdbDiscItems(items, 11, 'section_0');
    final again = pickTmdbDiscItems(items, 11, 'section_0');
    final other = pickTmdbDiscItems(items, 12, 'section_0');

    expect(first, hasLength(3));
    expect(again, first);
    expect(other, isNot(first));
  });

  test('不足 3 张时保持原样', () {
    final items = [_entry(1), _entry(2)];
    expect(pickTmdbDiscItems(items, 3, 'section_0'), items);
  });
}

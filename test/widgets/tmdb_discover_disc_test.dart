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

Finder _panel(String key) => find.byKey(ValueKey('tmdbDiscPanel_$key'));

Finder _island(String key) => find.byKey(ValueKey('tmdbDiscIsland_$key'));

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
          glassEnabled: false,
          focusNode: focusNode,
          onOpenSection: (section) => opened.add(section.key),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('视野只构建左中右三个分区，且只有高亮分区显示标题', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    expect(_panel('section_4'), findsOneWidget);
    expect(_panel('section_0'), findsOneWidget);
    expect(_panel('section_1'), findsOneWidget);
    expect(_panel('section_2'), findsNothing);
    expect(_panel('section_3'), findsNothing);
    expect(_island('section_4'), findsOneWidget);
    expect(_island('section_0'), findsOneWidget);
    expect(_island('section_1'), findsOneWidget);
    expect(find.text('分区0'), findsOneWidget);
    expect(find.text('分区4'), findsNothing);
    expect(find.text('分区1'), findsNothing);
    expect(find.byKey(const ValueKey('tmdbDiscSurface')), findsNothing);
    expect(find.byKey(const ValueKey('tmdbDiscEdgeFade')), findsNothing);
    expect(find.textContaining('查看全部'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('半盘高度紧凑且只保留三块贴纸', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final size = tester.getSize(find.byType(TmdbDiscCarousel));
    expect(size.height, greaterThan(200));
    expect(size.height, lessThan(260));
    expect(_island('section_4'), findsOneWidget);
    expect(_island('section_0'), findsOneWidget);
    expect(_island('section_1'), findsOneWidget);
  });

  testWidgets('分区数量增加后仍然只构建三个分区', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(7), opened: opened);

    expect(_panel('section_6'), findsOneWidget);
    expect(_panel('section_0'), findsOneWidget);
    expect(_panel('section_1'), findsOneWidget);
    expect(_panel('section_2'), findsNothing);
    expect(_panel('section_5'), findsNothing);
    expect(find.text('分区0'), findsOneWidget);
    expect(find.text('分区6'), findsNothing);
    expect(find.text('分区1'), findsNothing);
  });

  testWidgets('贴纸呈上拱半圆且中间轻微遮挡两侧', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final center = tester.getRect(_panel('section_0'));
    final left = tester.getRect(_panel('section_4'));
    final right = tester.getRect(_panel('section_1'));

    expect(center.top, lessThan(left.top));
    expect(center.top, lessThan(right.top));
    expect(center.overlaps(left), isTrue);
    expect(center.overlaps(right), isTrue);
    expect(center.center.dx, greaterThan(left.center.dx));
    expect(center.center.dx, lessThan(right.center.dx));
  });

  testWidgets('左右贴纸保持正立，不绕 Z 轴自转', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    for (final key in ['section_4', 'section_1']) {
      final box = tester.renderObject<RenderBox>(_panel(key));
      final topLeft = box.localToGlobal(Offset.zero);
      final topRight = box.localToGlobal(Offset(box.size.width, 0));
      expect((topLeft.dy - topRight.dy).abs(), lessThan(0.5));
    }
  });

  testWidgets('高亮标题悬浮在贴纸上方并与其重叠', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final title = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscActiveTitle')),
    );
    final center = tester.getRect(_panel('section_0'));

    expect(title.overlaps(center), isTrue);
    expect(title.center.dy, lessThan(center.center.dy));
  });

  testWidgets('左滑吸附到下一分区，标题只保留新的高亮分区', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    await tester.drag(
      find.byType(TmdbDiscCarousel),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(_panel('section_0'), findsOneWidget);
    expect(_panel('section_1'), findsOneWidget);
    expect(_panel('section_2'), findsOneWidget);
    expect(_panel('section_4'), findsNothing);
    expect(find.text('分区1'), findsOneWidget);
    expect(find.text('分区0'), findsNothing);
    expect(find.text('分区2'), findsNothing);
  });

  testWidgets('拖拽过半后不会同时出现两个标题', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TmdbDiscCarousel)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('tmdbDiscActiveTitle')),
      findsOneWidget,
    );
    expect(find.text('分区0'), findsNothing);
    expect(find.text('分区1'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
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
    expect(find.text('分区1'), findsOneWidget);
    expect(find.text('分区2'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['section_1']);
  });

  testWidgets('点击高亮标题打开对应栏目页', (tester) async {
    final opened = <String>[];
    await _pump(tester, sections: _sections(5), opened: opened);

    await tester.tap(
      find.byKey(const ValueKey('tmdbDiscActiveTitle')),
    );
    await tester.pump();

    expect(opened, ['section_0']);
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
}

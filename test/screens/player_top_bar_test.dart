import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_top_bar.dart';

import '../helpers/test_fakes.dart';

PlayerTopBar _bar({
  String title = '',
  String? networkSpeedText,
  bool showDecodeButton = false,
  bool decodeMenuOpen = false,
  bool glassEnabled = true,
  bool showVideoFitButton = false,
  bool showShare = false,
  bool showSubtitleStyleButton = true,
  bool subtitleStyleMenuOpen = false,
  VoidCallback? onToggleSubtitleStyle,
  bool showSpeedButton = false,
  String speedLabel = '1.0x',
  bool speedMenuOpen = false,
  FocusNode? speedButtonFocusNode,
  VoidCallback? onToggleSpeed,
  bool showRotateButton = false,
  VoidCallback? onRotate,
}) =>
    PlayerTopBar(
      title: title,
      networkSpeedText: networkSpeedText,
      showDecodeButton: showDecodeButton,
      decodeMenuOpen: decodeMenuOpen,
      glassEnabled: glassEnabled,
      showVideoFitButton: showVideoFitButton,
      videoFitIcon: Icons.fit_screen,
      videoFitLabel: '自适应',
      onCycleVideoFit: () {},
      showShare: showShare,
      onBack: () {},
      onToggleDecode: () {},
      onShare: () {},
      showSubtitleStyleButton: showSubtitleStyleButton,
      subtitleStyleMenuOpen: subtitleStyleMenuOpen,
      onToggleSubtitleStyle: onToggleSubtitleStyle,
      showSpeedButton: showSpeedButton,
      speedLabel: speedLabel,
      speedMenuOpen: speedMenuOpen,
      speedButtonFocusNode: speedButtonFocusNode,
      onToggleSpeed: onToggleSpeed,
      showRotateButton: showRotateButton,
      onRotate: onRotate,
    );

Widget _host(Widget child, {AppSettings settings = const AppSettings()}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
  );
  addTearDown(container.dispose);
  // TvFocusable 是 ConsumerWidget（读 tvMode provider）
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('PlayerScreen 静态格式化（顶栏信息）', () {
    test('formatMediaTitle：电影 = 片名', () {
      const info = EpisodeInfo(id: '1', name: '盗梦空间');
      expect(info.isMovie, isTrue);
      expect(PlayerScreen.formatMediaTitle(info), '盗梦空间');
    });

    test('formatMediaTitle：剧集 = 剧名 – S00E01', () {
      const info = EpisodeInfo(
        id: '1',
        name: '斯巴达克斯',
        season: 0,
        number: 1,
        seriesName: '斯巴达克斯',
      );
      expect(info.isMovie, isFalse);
      expect(PlayerScreen.formatMediaTitle(info), '斯巴达克斯 – S00E01');
    });

    test('formatMediaTitle：季集补零（S01E02）', () {
      const info = EpisodeInfo(
        id: '1',
        name: '集名',
        season: 1,
        number: 2,
        seriesName: '剧名',
      );
      expect(PlayerScreen.formatMediaTitle(info), '剧名 – S01E02');
    });

    test('formatMediaTitle：剧名为空回退片名', () {
      const info = EpisodeInfo(id: '1', name: '直链影片', season: 1, number: 3);
      expect(PlayerScreen.formatMediaTitle(info), '直链影片');
    });

    test('episodeCode 补零', () {
      expect(PlayerScreen.episodeCode(0, 1), 'S00E01');
      expect(PlayerScreen.episodeCode(12, 34), 'S12E34');
    });
  });

  group('mediaTitleAt（详情页开房白屏回归）', () {
    const movie = EpisodeInfo(id: 'm1', name: '完美世界剧场版');
    const series = EpisodeInfo(
      id: 'e1',
      name: '第一集',
      season: 1,
      number: 2,
      seriesName: '剧名',
    );
    final episodes = [movie, series];

    test('index=-1 + 非空列表 → 空串（初进开房的 RangeError 根因）', () {
      expect(PlayerScreen.mediaTitleAt(episodes, -1), '');
    });

    test('index 越界 → 空串', () {
      expect(PlayerScreen.mediaTitleAt(episodes, 2), '');
      expect(PlayerScreen.mediaTitleAt(episodes, 99), '');
    });

    test('空列表 → 空串', () {
      expect(PlayerScreen.mediaTitleAt(const [], -1), '');
      expect(PlayerScreen.mediaTitleAt(const [], 0), '');
    });

    test('有效下标 → 正常标题', () {
      expect(PlayerScreen.mediaTitleAt(episodes, 0), '完美世界剧场版');
      expect(PlayerScreen.mediaTitleAt(episodes, 1), '剧名 – S01E02');
    });
  });

  group('PlayerTopBar', () {
    testWidgets('标题与网速回显渲染', (tester) async {
      await tester.pumpWidget(_host(_bar(
        title: '斯巴达克斯 – S00E01',
        networkSpeedText: '4.89 MB/s',
      )));
      expect(find.byKey(const ValueKey('playerTitle')), findsOneWidget);
      expect(find.text('斯巴达克斯 – S00E01'), findsOneWidget);
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsOneWidget);
      expect(find.text('4.89 MB/s'), findsOneWidget);
    });

    testWidgets('标题为空不渲染文本；网速 null（设置关闭）不渲染', (tester) async {
      await tester.pumpWidget(_host(_bar()));
      expect(find.byKey(const ValueKey('playerTitle')), findsNothing);
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsNothing);
    });

    testWidgets('分享按钮按 showShare 显隐', (tester) async {
      await tester.pumpWidget(_host(_bar(showShare: false)));
      expect(find.byKey(const ValueKey('playerShareButton')), findsNothing);
      await tester.pumpWidget(_host(_bar(showShare: true)));
      expect(find.byKey(const ValueKey('playerShareButton')), findsOneWidget);
    });

    testWidgets('画面比例按钮按 showVideoFitButton 显隐（解码右侧）', (tester) async {
      await tester.pumpWidget(_host(_bar(showVideoFitButton: false)));
      expect(find.byIcon(Icons.fit_screen), findsNothing);
      await tester.pumpWidget(_host(_bar(showVideoFitButton: true)));
      expect(find.byIcon(Icons.fit_screen), findsOneWidget);
      expect(find.byTooltip('自适应'), findsOneWidget);
    });
  });

  group('字幕样式按钮（网速与解码之间）', () {
    testWidgets('按钮渲染且位于网速右侧、解码左侧', (tester) async {
      await tester.pumpWidget(_host(_bar(
        networkSpeedText: '4.89 MB/s',
        showDecodeButton: true,
      )));

      final style = find.byKey(const ValueKey('playerSubtitleStyleButton'));
      expect(style, findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);

      final speedX = tester
          .getTopLeft(find.byKey(const ValueKey('playerNetworkSpeed')))
          .dx;
      final styleX = tester.getTopLeft(style).dx;
      final decodeX = tester
          .getTopLeft(find.byKey(const ValueKey('playerDecodeButton')))
          .dx;
      expect(speedX, lessThan(styleX), reason: '网速在样式按钮左侧');
      expect(styleX, lessThan(decodeX), reason: '样式按钮在解码左侧');
    });

    testWidgets('网速关闭（null）时按钮仍渲染', (tester) async {
      await tester.pumpWidget(_host(_bar(
        networkSpeedText: null,
        showDecodeButton: true,
      )));
      expect(
        find.byKey(const ValueKey('playerSubtitleStyleButton')),
        findsOneWidget,
      );
    });

    testWidgets('按 showSubtitleStyleButton 显隐；点击触发回调', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_host(_bar(
          showSubtitleStyleButton: false,
          onToggleSubtitleStyle: () => toggled = true)));
      expect(
        find.byKey(const ValueKey('playerSubtitleStyleButton')),
        findsNothing,
      );

      await tester.pumpWidget(_host(_bar(
          showSubtitleStyleButton: true,
          onToggleSubtitleStyle: () => toggled = true)));
      await tester.tap(
        find.byKey(const ValueKey('playerSubtitleStyleButton')),
      );
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });

    testWidgets('展开态描边高亮（同解码胶囊）', (tester) async {
      BoxDecoration decorationOf(WidgetTester t) {
        final container = t.widget<Container>(
          find
              .descendant(
                of: find.byKey(const ValueKey('playerSubtitleStyleButton')),
                matching: find.byType(Container),
              )
              .first,
        );
        return container.decoration! as BoxDecoration;
      }

      await tester.pumpWidget(
          _host(_bar(subtitleStyleMenuOpen: false, glassEnabled: true)));
      await tester.pumpAndSettle();
      final closed = decorationOf(tester);
      expect(closed.border!.top.color, isNot(const Color(0xFF6366F1)));
      expect(closed.boxShadow, isNull);

      await tester.pumpWidget(
          _host(_bar(subtitleStyleMenuOpen: true, glassEnabled: true)));
      await tester.pumpAndSettle();
      final open = decorationOf(tester);
      expect(open.border!.top.color, const Color(0xFF6366F1));
      expect(open.boxShadow, isNotNull, reason: '展开态 accent 外发光');
    });
  });

  group('倍速按钮（网速右侧）', () {
    testWidgets('渲染于网速右侧、字幕样式左侧，显示当前倍速标签', (tester) async {
      await tester.pumpWidget(_host(_bar(
        networkSpeedText: '4.89 MB/s',
        showSpeedButton: true,
        speedLabel: '1.5x',
        showDecodeButton: true,
      )));

      final speed = find.byKey(const ValueKey('playerTopSpeedButton'));
      expect(speed, findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);

      final netX = tester
          .getTopLeft(find.byKey(const ValueKey('playerNetworkSpeed')))
          .dx;
      final speedX = tester.getTopLeft(speed).dx;
      final styleX = tester
          .getTopLeft(find.byKey(const ValueKey('playerSubtitleStyleButton')))
          .dx;
      expect(netX, lessThan(speedX), reason: '倍速在网速右侧');
      expect(speedX, lessThan(styleX), reason: '倍速在字幕样式左侧');
    });

    testWidgets('按 showSpeedButton 显隐；点击触发回调', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_host(_bar(showSpeedButton: false)));
      expect(
        find.byKey(const ValueKey('playerTopSpeedButton')),
        findsNothing,
      );

      await tester.pumpWidget(_host(_bar(
        showSpeedButton: true,
        onToggleSpeed: () => toggled = true,
      )));
      await tester.tap(find.byKey(const ValueKey('playerTopSpeedButton')));
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });

    testWidgets('展开态图标与文字高亮为 accent', (tester) async {
      await tester.pumpWidget(_host(_bar(
        showSpeedButton: true,
        speedLabel: '2.0x',
        speedMenuOpen: false,
      )));
      final closedIcon = tester.widget<Icon>(find.byIcon(Icons.speed));
      expect(closedIcon.color, Colors.white);

      await tester.pumpWidget(_host(_bar(
        showSpeedButton: true,
        speedLabel: '2.0x',
        speedMenuOpen: true,
      )));
      final openIcon = tester.widget<Icon>(find.byIcon(Icons.speed));
      expect(openIcon.color, const Color(0xFF6366F1));
    });
  });

  group('转屏按钮（画面比例右侧）', () {
    testWidgets('渲染于画面比例右侧，图标与 tooltip 正确', (tester) async {
      await tester.pumpWidget(_host(_bar(
        showVideoFitButton: true,
        showRotateButton: true,
      )));

      final rotate = find.byKey(const ValueKey('playerTopRotateButton'));
      expect(rotate, findsOneWidget);
      expect(find.byIcon(Icons.screen_rotation_alt), findsOneWidget);
      expect(find.byTooltip('旋转屏幕'), findsOneWidget);

      final fitX = tester.getTopLeft(find.byIcon(Icons.fit_screen)).dx;
      final rotateX = tester.getTopLeft(rotate).dx;
      expect(fitX, lessThan(rotateX), reason: '转屏在画面比例右侧');
    });

    testWidgets('按 showRotateButton 显隐；点击触发回调', (tester) async {
      var rotated = false;
      await tester.pumpWidget(_host(_bar(showRotateButton: false)));
      expect(
        find.byKey(const ValueKey('playerTopRotateButton')),
        findsNothing,
      );

      await tester.pumpWidget(_host(_bar(
        showRotateButton: true,
        onRotate: () => rotated = true,
      )));
      await tester.tap(find.byKey(const ValueKey('playerTopRotateButton')));
      await tester.pumpAndSettle();
      expect(rotated, isTrue);
    });
  });

  group('解码图标方块（B2 图标化）', () {
    BoxDecoration _chipDecoration(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('playerDecodeButton')),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('图标 only 无文字，点击触发 onToggleDecode', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_host(PlayerTopBar(
        title: '',
        networkSpeedText: null,
        showDecodeButton: true,
        decodeMenuOpen: false,
        glassEnabled: true,
        showVideoFitButton: false,
        videoFitIcon: Icons.fit_screen,
        videoFitLabel: '自适应',
        onCycleVideoFit: () {},
        showShare: false,
        onBack: () {},
        onToggleDecode: () => toggled = true,
        onShare: () {},
      )));

      expect(find.byKey(const ValueKey('playerDecodeButton')), findsOneWidget);
      expect(find.byIcon(Icons.memory), findsOneWidget);
      expect(find.byType(Text), findsNothing, reason: '文字已移入解码面板，顶栏纯图标');
      await tester.tap(find.byKey(const ValueKey('playerDecodeButton')));
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });

    testWidgets('玻璃开：收起白细描边无发光 / 展开 accent 描边 + 外发光', (tester) async {
      await tester.pumpWidget(
          _host(_bar(showDecodeButton: true, decodeMenuOpen: false)));
      await tester.pumpAndSettle();
      final closed = _chipDecoration(tester);
      expect(closed.border!.top.width, 0.8);
      expect(closed.border!.top.color, isNot(const Color(0xFF6366F1)));
      expect(closed.boxShadow, isNull);
      expect(closed.gradient, isNotNull, reason: '玻璃渐变底');

      await tester.pumpWidget(
          _host(_bar(showDecodeButton: true, decodeMenuOpen: true)));
      await tester.pumpAndSettle();
      final open = _chipDecoration(tester);
      expect(open.border!.top.color, const Color(0xFF6366F1));
      expect(open.border!.top.width, 1.5);
      expect(open.boxShadow, isNotNull, reason: '展开态 accent 外发光');
    });

    testWidgets('玻璃关（降级）：收起白 15% 平底 / 展开实心 accent', (tester) async {
      await tester.pumpWidget(_host(_bar(
          showDecodeButton: true, decodeMenuOpen: false, glassEnabled: false)));
      await tester.pumpAndSettle();
      final closed = _chipDecoration(tester);
      expect(closed.color, Colors.white.withValues(alpha: 0.15));
      expect(closed.gradient, isNull);
      expect(closed.border, isNull);

      await tester.pumpWidget(_host(_bar(
          showDecodeButton: true, decodeMenuOpen: true, glassEnabled: false)));
      await tester.pumpAndSettle();
      final open = _chipDecoration(tester);
      expect(open.color, const Color(0xFF6366F1));
      expect(open.boxShadow, isNull);
    });
  });
}

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
  bool showShare = false,
  bool locked = false,
  VoidCallback? onToggleLock,
}) =>
    PlayerTopBar(
      title: title,
      networkSpeedText: networkSpeedText,
      showDecodeButton: showDecodeButton,
      decodeModeLabel: 'Auto',
      decodeMenuOpen: false,
      showShare: showShare,
      locked: locked,
      onBack: () {},
      onToggleDecode: () {},
      onShare: () {},
      onToggleLock: onToggleLock ?? () {},
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
  group('PlayerScreen 静态格式化（顶栏信息/网速）', () {
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

    test('formatMbps：kbps → Mbps 两位小数', () {
      expect(PlayerScreen.formatMbps(0), '0.00 Mbps');
      expect(PlayerScreen.formatMbps(4890), '4.89 Mbps');
      expect(PlayerScreen.formatMbps(12345), '12.35 Mbps');
    });
  });

  group('PlayerTopBar', () {
    testWidgets('标题与网速回显渲染', (tester) async {
      await tester.pumpWidget(_host(_bar(
        title: '斯巴达克斯 – S00E01',
        networkSpeedText: '4.89 Mbps',
      )));
      expect(find.byKey(const ValueKey('playerTitle')), findsOneWidget);
      expect(find.text('斯巴达克斯 – S00E01'), findsOneWidget);
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsOneWidget);
      expect(find.text('4.89 Mbps'), findsOneWidget);
    });

    testWidgets('标题为空不渲染文本；网速 null（设置关闭）不渲染', (tester) async {
      await tester.pumpWidget(_host(_bar()));
      expect(find.byKey(const ValueKey('playerTitle')), findsNothing);
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsNothing);
    });

    testWidgets('锁按钮：未锁 lock_open，点击回调上锁', (tester) async {
      var lockedCalls = 0;
      await tester.pumpWidget(_host(_bar(onToggleLock: () => lockedCalls++)));
      final icon =
          tester.widget<Icon>(find.byKey(const ValueKey('playerLockButton')));
      expect(icon.icon, Icons.lock_open);
      await tester.tap(find.byKey(const ValueKey('playerLockButton')));
      expect(lockedCalls, 1);
    });

    testWidgets('锁按钮：locked 时图标为 lock', (tester) async {
      await tester.pumpWidget(_host(_bar(locked: true)));
      final icon =
          tester.widget<Icon>(find.byKey(const ValueKey('playerLockButton')));
      expect(icon.icon, Icons.lock);
    });

    testWidgets('分享按钮按 showShare 显隐', (tester) async {
      await tester.pumpWidget(_host(_bar(showShare: false)));
      expect(find.byKey(const ValueKey('playerShareButton')), findsNothing);
      await tester.pumpWidget(_host(_bar(showShare: true)));
      expect(find.byKey(const ValueKey('playerShareButton')), findsOneWidget);
    });
  });
}

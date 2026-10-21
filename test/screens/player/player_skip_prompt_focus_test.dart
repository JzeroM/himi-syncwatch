import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/manual_segment_store.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

import '../../helpers/test_fakes.dart';

/// TV 跳过片头/片尾提示焦点回归：
/// - 全屏 PlayerHotkey 不参与方向键遍历，避免从提示按方向键落到不可见节点；
/// - 提示自动消失后焦点回落到可见控制条，而不是不可见热键层。
class _FakePlayerAdapter implements PlayerAdapter {
  @override
  AdapterPlaybackState state = AdapterPlaybackState.stopped;

  int positionMs = 0;
  int _durationMs = 0;

  @override
  Future<void> seek({required int positionMs}) async {
    this.positionMs = positionMs;
  }

  @override
  set media(String uri) {}
  @override
  Future<void> prepare({int startMs = 0}) async {}
  @override
  int get position => positionMs;
  @override
  int get duration => _durationMs;
  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo(duration: _durationMs);

  void emitLoaded(int durationMs) {
    _durationMs = durationMs;
    _statusCtrl.add((
      oldValue: AdapterMediaStatus.loading,
      newValue: AdapterMediaStatus.loaded,
    ));
  }

  final _statusCtrl = StreamController<
      ({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>.broadcast();
  @override
  double volume = 0.8;
  @override
  double playbackRate = 1.0;
  @override
  AdapterMediaStatus get mediaStatus => AdapterMediaStatus.loading;
  @override
  int buffered() => 0;
  @override
  final ValueNotifier<int?> textureId = ValueNotifier<int?>(1);
  @override
  int get nativeHandle => 1;
  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) async => 1;
  @override
  Future<Size?> get textureSize async => const Size(1920, 1080);
  @override
  void setColorSpace(AdapterColorSpace cs) {}
  @override
  void renderVideo() {}
  @override
  List<int> activeAudioTracks = const [];
  @override
  List<int> activeSubtitleTracks = const [];
  @override
  void setProperty(String name, String value) {}
  @override
  String? getProperty(String name) => null;
  @override
  void setHttpHeaders(Map<String, String> headers) {}
  @override
  List<String> videoDecoders = const [];
  @override
  List<String> audioDecoders = const [];
  @override
  set audioBackends(List<String> backends) {}
  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) {}
  @override
  Future<void> setMedia(String uri, {required AdapterMediaType type}) async {}
  @override
  Future<Uint8List?> snapshot({int? width, int? height}) async => null;
  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => const Stream.empty();
  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => _statusCtrl.stream;
  @override
  Stream<AdapterMediaEvent> get onEvent => const Stream.empty();
  @override
  void dispose() {
    _statusCtrl.close();
  }
}

MediaItem _movieWithIntroChapter() => MediaItem(
      id: 'mv1',
      name: '片头测试影片',
      type: 'Movie',
      runTimeTicks: 36000000000,
      mediaSources: [
        MediaSource(id: 's1', name: '默认'),
      ],
      chapters: const [
        MediaChapter(startMs: 0, name: '片头', markerType: 'IntroStart'),
        MediaChapter(startMs: 90000, name: '正片', markerType: 'IntroEnd'),
      ],
    );

class _FakeManualSegments implements ManualSegmentRepository {
  @override
  Future<ManualSegmentRecord?> get(String key) async => null;

  @override
  Future<void> clearCredits(String key) async {}

  @override
  Future<void> clearIntro(String key) async {}

  @override
  Future<ManualSegmentRecord> setCreditsStart({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int creditsStartMs,
  }) =>
      throw UnimplementedError();

  @override
  Future<ManualSegmentRecord> setIntroEnd({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int introEndMs,
  }) =>
      throw UnimplementedError();
}

EmbyServerConfig _authedServer() => EmbyServerConfig(
      id: 'cfg1',
      serverUrl: 'http://main:8096',
      serverName: 'NAS',
      serverId: 'srv1',
      username: 'u',
      accessToken: 'tok',
      userId: 'uid',
    );

void _mockPluginChannels(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  messenger.setMockMethodCallHandler(brightness, (call) async {
    if (call.method == 'getApplicationScreenBrightness') return 0.8;
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(brightness, null));

  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  messenger.setMockMessageHandler(
    wakelockChannel,
    (message) async =>
        const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
  addTearDown(() => messenger.setMockMessageHandler(wakelockChannel, null));
}

Future<(ProviderContainer, _FakePlayerAdapter)> _pumpPlayer(
    WidgetTester tester) async {
  _mockPluginChannels(tester);
  final player = _FakePlayerAdapter();
  PlayerEngineFactory.debugCreateOverride =
      (engine, {erikaOutputMode = ErikaOutputMode.sdr}) => player;
  addTearDown(() => PlayerEngineFactory.debugCreateOverride = null);

  final item = _movieWithIntroChapter();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(
            const AppSettings(
              tvMode: true,
              skipIntroOutroEnabled: true,
            ),
          )),
      embyServiceProvider.overrideWith((ref) => FakeEmbyService(item: item)),
      embyConfigProvider.overrideWith(
          (ref) => EmbyConfigNotifier()..setConfig(_authedServer())),
    ],
  );
  addTearDown(container.dispose);
  container.read(pendingRoomMovieProvider.notifier).state = {
    'id': item.id,
    'name': item.name,
    'poster': '',
    'serverId': null,
  };

  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      // 与 lib/core/app.dart 一致：生产 TV 方向键由 TvRemoteShell 接管。
      // 此前测试直接挂 MaterialApp，漏掉自定义方向遍历路径。
      builder: (context, child) =>
          TvRemoteShell(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(),
    ),
  ));
  navigatorKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => PlayerScreen(
      itemId: 'mv1',
      isHost: true,
      manualSegmentRepository: _FakeManualSegments(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  return (container, player);
}

Future<void> _showSkipPrompt(
    WidgetTester tester, _FakePlayerAdapter player) async {
  player.emitLoaded(3600000);
  await tester.pump();
  player.state = AdapterPlaybackState.playing;
  player.positionMs = 0;
  await tester.pump(const Duration(milliseconds: 600));
  // 片头提示门槛由 Stopwatch（真实时间）判定，fake pump 不推进它。
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3100)));
  player.positionMs = 5000;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.text('跳过片头'), findsOneWidget);
  expect(
    FocusManager.instance.primaryFocus?.debugLabel,
    'SegmentSkipPrompt',
    reason: '提示出现后自动落焦',
  );
}

Future<void> _disposePlayer(WidgetTester tester) async {
  // 先让跳过提示 8 秒计时器到点，避免卸载后仍有 pending timer。
  await tester.pump(const Duration(seconds: 9));
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('TV：跳过提示上按方向键显式回到可见进度条', (tester) async {
    final (_, player) = await _pumpPlayer(tester);
    await _showSkipPrompt(tester, player);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PlayerSeekSlider',
      reason: '提示上方向键直接落到可见控制条，不能进不可见热键层',
    );
    expect(find.text('跳过片头'), findsOneWidget, reason: '按方向键不误关提示');

    // 提示随后自动消失，焦点仍须留在可见进度条。
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('跳过片头'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PlayerSeekSlider',
      reason: '提示消失不改变已可见的焦点',
    );

    await _disposePlayer(tester);
  });

  testWidgets('TV：焦点已到不可见根节点时，提示消失也会恢复焦点', (tester) async {
    final (_, player) = await _pumpPlayer(tester);
    await _showSkipPrompt(tester, player);

    // 模拟方向键/焦点历史把焦点送到 skipTraversal 根锚点（不可见）。
    final controlsRoot = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'PlayerControlsRoot');
    expect(controlsRoot, findsOneWidget);
    tester.widget<Focus>(controlsRoot).focusNode!.requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PlayerControlsRoot',
    );

    // 不再按左键救回，直接等提示 8 秒自动消失。
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(find.text('跳过片头'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PlayerSeekSlider',
      reason: '提示消失时须把不可见焦点恢复到可见控件',
    );

    // 恢复后重置自动隐藏计时，短时间内控制条仍可见。
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('跳过片头'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PlayerSeekSlider',
      reason: '重置 5 秒隐藏计时，焦点不会立刻再次消失',
    );

    await _disposePlayer(tester);
  });

  testWidgets('TV：跳过提示自动消失后焦点回到可见控制条', (tester) async {
    final (_, player) = await _pumpPlayer(tester);
    await _showSkipPrompt(tester, player);

    // 提示自身 8 秒计时到点消失
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(find.text('跳过片头'), findsNothing);
    final focus = FocusManager.instance.primaryFocus;
    expect(focus?.debugLabel, isNot('PlayerHotkey'),
        reason: '控制条可见时不能回落不可见热键层');
    expect(focus?.debugLabel, isNotNull, reason: '焦点不能悬空');

    await _disposePlayer(tester);
  });
}

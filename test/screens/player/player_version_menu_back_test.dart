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
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/version_menu_panel.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../../helpers/test_fakes.dart';

/// 播放器 TV 回归（v1.2.24/v1.2.25）：
/// - 版本面板返回键：多版本播放器打开「版本」面板后按返回键，面板须
///   关闭且焦点归还版本按钮（`TvBackConfirm.onBack` 互斥列表漏了
///   `_showVersionMenu`，与 v1.1.2xx 其他选择器面板同款收口，647ac50）；
/// - 慢流起播隐藏控件：慢流首开超过 5s 时，进入页时的自动隐藏计时器
///   已空转跳过（state != playing），起播成功须重新起算，否则控件常驻。
class _FakeStreamingPlayerAdapter implements PlayerAdapter {
  _FakeStreamingPlayerAdapter({this.prepareDelay = Duration.zero});

  /// 模拟慢流：prepare（真实设备上等价于 avformat_open_input 拉流）耗时。
  final Duration prepareDelay;

  @override
  AdapterPlaybackState state = AdapterPlaybackState.stopped;
  @override
  Future<void> seek({required int positionMs}) async {}
  @override
  set media(String uri) {}
  @override
  Future<void> prepare({int startMs = 0}) async {
    if (prepareDelay > Duration.zero) {
      await Future<void>.delayed(prepareDelay);
    }
  }

  @override
  int get position => 0;
  @override
  int get duration => _durationMs;
  int _durationMs = 0;
  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo(duration: _durationMs);

  /// 模拟 `loaded` 事件：时长就绪（真实链路由 mdk MediaStatus 驱动）。
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

MediaItem _multiSourceMovie() => MediaItem(
      id: 'mv1',
      name: '多版本影片',
      type: 'Movie',
      mediaSources: [
        MediaSource(id: 'sv_a', name: 'HDR 版', size: 1073741824),
        MediaSource(id: 'sv_b', name: 'SDR 版', size: 1073741823),
      ],
    );

EmbyServerConfig _authedServer() => EmbyServerConfig(
      id: 'cfg1',
      serverUrl: 'http://main:8096',
      serverName: 'NAS',
      serverId: 'srv1',
      username: 'u',
      accessToken: 'tok',
      userId: 'uid',
    );

/// 播放器起播链会 await 插件通道（WakelockPlus/ScreenBrightness）；
/// 测试环境未挂引擎侧实现时这些 Future 永不完成，会卡住起播。
/// 用静态桩应答通道，让 `_initPlayerProperties` 正常返回。
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

/// 起播（含 mock 插件通道 / provider 覆盖 / Navigator.push 帧序）。
/// 返回 (container, fake player)，慢流用例可注入 prepare 延迟并补发事件。
Future<(ProviderContainer, _FakeStreamingPlayerAdapter)> _pumpPlayer(
  WidgetTester tester, {
  Duration prepareDelay = Duration.zero,
  AppSettings settings = const AppSettings(tvMode: true),
}) async {
  _mockPluginChannels(tester);
  final player = _FakeStreamingPlayerAdapter(prepareDelay: prepareDelay);
  PlayerEngineFactory.debugCreateOverride =
      (engine, {erikaOutputMode = ErikaOutputMode.sdr}) => player;
  addTearDown(() => PlayerEngineFactory.debugCreateOverride = null);

  final item = _multiSourceMovie();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyServiceProvider.overrideWith((ref) => FakeEmbyService(item: item)),
      embyConfigProvider.overrideWith(
          (ref) => EmbyConfigNotifier()..setConfig(_authedServer())),
    ],
  );
  addTearDown(container.dispose);
  // 单人电影走「房主」路径：详情页通过 pendingMovie 传条目后跳播放器。
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
      home: const Scaffold(),
    ),
  ));
  // 经 Navigator.push 进播放器，贴近真机「详情页 → 播放器」的构建帧序
  // （initState 里消费 pending provider，清理已延后到帧末）。
  navigatorKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => const PlayerScreen(itemId: 'mv1', isHost: true),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  return (container, player);
}

void main() {
  testWidgets('TV：返回键收起版本面板并把焦点还给版本按钮（v1.2.24）', (tester) async {
    await _pumpPlayer(tester);

    final versionIcon = find.byIcon(Icons.high_quality);
    expect(versionIcon, findsOneWidget, reason: '多版本 → 底栏出现版本按钮');
    final button = tester.widget<TvFocusable>(
      find.ancestor(of: versionIcon, matching: find.byType(TvFocusable)),
    );
    expect(button.focusNode, isNotNull, reason: '版本按钮带焦点节点');

    button.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(VersionMenuPanel), findsOneWidget, reason: '版本面板已打开');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(VersionMenuPanel), findsNothing,
        reason: '返回键收起版本面板（修复前该面板漏在 onBack 互斥列表外）');
    expect(button.focusNode!.hasFocus, isTrue,
        reason: '焦点回到版本按钮（遥控器可立即 OK 重开）');

    // 卸载页面并推进假时钟，避免 "Timer still pending" 报错
    // （起播后遗留 2s DV 探测 / 500ms 换源锁等一次性延迟）
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('TV：进度条长按 OK 只开标记面板，不切换播放状态', (tester) async {
    final (_, player) = await _pumpPlayer(
      tester,
      settings: const AppSettings(
        tvMode: true,
        skipIntroOutroEnabled: true,
      ),
    );
    player.state = AdapterPlaybackState.playing;

    final seekFocus = find.byWidgetPredicate(
      (w) => w is Focus && w.focusNode?.debugLabel == 'PlayerSeekSlider',
    );
    expect(seekFocus, findsOneWidget);
    tester.widget<Focus>(seekFocus).focusNode!.requestFocus();
    await tester.pump();

    await simulateKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('设置片头'), findsOneWidget, reason: '长按 OK 打开标记面板');
    await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(find.text('设置片头'), findsOneWidget, reason: '方向键操作后面板仍在');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf('SegmentMarkFirst', 'TvFocusable'),
      reason: '方向键操作后焦点仍留在面板内',
    );

    expect(
      player.state,
      AdapterPlaybackState.playing,
      reason: '长按标记不应误触播放/暂停',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('TV：慢流首开超过 5s，起播后控件仍按时自动隐藏（v1.2.25）', (tester) async {
    // 真机日志：4K/弱网 avformat_open_input 约 10s，进入页时的自动隐藏
    // 计时器（5s）先到点且被 state != playing 跳过；旧实现不重开计时，
    // 控件常驻（用户感知「控件自己冒出来」）。修复：起播成功重新起算。
    final (_, player) =
        await _pumpPlayer(tester, prepareDelay: const Duration(seconds: 6));

    final controls = find.byIcon(Icons.subtitles);
    expect(controls, findsOneWidget, reason: '进入页控件可见');

    // 跨过首次 5s 自动隐藏（此时仍在拉流，state != playing → 跳过）
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 2));
    expect(controls, findsOneWidget, reason: '起播前控件保持可见（可点返回）');

    // 起播完成（load 链 setState ready + state=playing）后时长就绪
    player.emitLoaded(7200000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controls, findsOneWidget, reason: '起播瞬间仍可见');

    // 起播后重新计 5s：应自动隐藏
    await tester.pump(const Duration(seconds: 6));
    expect(controls, findsNothing, reason: '慢流起播后重新起算，5s 无操作自动隐藏（修复前常驻）');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  });
}

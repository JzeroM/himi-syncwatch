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
import 'package:himi_syncwatch/services/manual_segment_store.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

import '../../helpers/test_fakes.dart';

/// 播放器未加载完就返回的生命周期回归（v1.2.53）。
///
/// 根因：`_loadStream` 在 `await prepare()` 后未复查页面状态，直接写
/// playbackRate。若用户此时返回，dispose 已释放 mdk，prepare 晚到后再写
/// 原生对象会 use-after-free 闪退（TV 盒子慢流更易命中）。本测试用可挂起
/// 的假适配器复现该时序，断言卸载后不再发生任何加载续体写入。
class _HangingPreparePlayerAdapter
    implements PlayerAdapter, AsyncDisposablePlayer {
  final Completer<void> prepareStarted = Completer<void>();
  final Completer<void> prepareGate = Completer<void>();

  int playbackRateWrites = 0;
  int disposeCalls = 0;
  bool disposed = false;

  @override
  AdapterPlaybackState state = AdapterPlaybackState.stopped;

  @override
  Future<void> prepare({int startMs = 0}) async {
    if (!prepareStarted.isCompleted) prepareStarted.complete();
    await prepareGate.future;
  }

  @override
  Future<void> seek({required int positionMs}) async {}

  @override
  set media(String uri) {}

  @override
  int get position => 0;

  @override
  int get duration => 0;

  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo.empty;

  @override
  double volume = 0.8;

  double _playbackRate = 1.0;

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    _playbackRate = value;
    playbackRateWrites++;
  }

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
      get onMediaStatus => const Stream.empty();

  @override
  Stream<AdapterMediaEvent> get onEvent => const Stream.empty();

  @override
  void dispose() {
    disposeCalls++;
    disposed = true;
  }

  @override
  Future<void> disposeAsync() async {
    disposeCalls++;
    disposed = true;
  }
}

class _NoopManualSegments implements ManualSegmentRepository {
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

MediaItem _movie() => MediaItem(
      id: 'mv-load',
      name: '加载中返回测试',
      type: 'Movie',
      runTimeTicks: 36000000000,
      mediaSources: [
        MediaSource(id: 's1', name: '默认'),
      ],
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

void main() {
  testWidgets('加载中返回：prepare 晚到不得再写 playbackRate，且只释放一次', (tester) async {
    _mockPluginChannels(tester);
    final player = _HangingPreparePlayerAdapter();
    PlayerEngineFactory.debugCreateOverride =
        (engine, {erikaOutputMode = ErikaOutputMode.sdr}) => player;
    addTearDown(() => PlayerEngineFactory.debugCreateOverride = null);

    final item = _movie();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings()),
        ),
        embyServiceProvider.overrideWith((ref) => FakeEmbyService(item: item)),
        embyConfigProvider.overrideWith(
          (ref) => EmbyConfigNotifier()..setConfig(_authedServer()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(pendingRoomMovieProvider.notifier).state = {
      'id': item.id,
      'name': item.name,
      'poster': '',
      'serverId': null,
    };

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: PlayerScreen(
          itemId: item.id,
          isHost: true,
          manualSegmentRepository: _NoopManualSegments(),
        ),
      ),
    ));
    // initState 的加载在 post-frame 启动：逐帧推进直到进入 prepare。
    for (var i = 0; i < 30 && !player.prepareStarted.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(player.prepareStarted.isCompleted, isTrue,
        reason: '已进入真实加载链路并停在 prepare');

    // 加载未完成时返回：dispose 会先走 150ms 延迟释放。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(player.disposeCalls, 1, reason: '页面销毁后应释放一次播放器');

    // prepare 此刻才返回：旧实现会继续写 playbackRate（原生已释放 → 闪退）。
    player.prepareGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.playbackRateWrites, 0, reason: '卸载后 prepare 续体不得再触碰播放器');
    expect(player.disposeCalls, 1, reason: '释放不能被重复触发');
  });
}

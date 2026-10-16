import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

import '../../helpers/test_fakes.dart';

/// PlayerScreen 播放器事件订阅的生命周期回归（v1.2.6）。
///
/// 背景：`_setupPlayerListeners` 里 onStateChanged/onMediaStatus 一直被存
/// 字段并在引擎重建/页面销毁时取消，但 onEvent 曾是**匿名订阅**（从不
/// 取消）——每次 HDR 路由重建引擎都会在旧播放器的 `_eventCb` 上多挂一个
/// 永久监听（订阅/闭包泄漏，并使上游 `hasListener` 恒真）。
///
/// 本测试以真实 `PlayerScreen` 挂载一个可观测 listener 数的假适配器，
/// 断言：挂载后三类事件流均被订阅；widget 销毁后全部取消（无残留监听）。
///
/// 用 `PlayerEngineFactory.debugCreateOverride` 注入假适配器，避免在
/// 单测中实例化真实原生引擎（mdk 需要 libmdk）。
class _FakeStreamingPlayerAdapter implements PlayerAdapter {
  final StreamController<
      ({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      stateCtrl = StreamController.broadcast();
  final StreamController<
      ({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      statusCtrl = StreamController.broadcast();
  final StreamController<AdapterMediaEvent> eventCtrl =
      StreamController.broadcast();

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => stateCtrl.stream;
  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => statusCtrl.stream;
  @override
  Stream<AdapterMediaEvent> get onEvent => eventCtrl.stream;

  bool get hasAnyListener =>
      stateCtrl.hasListener || statusCtrl.hasListener || eventCtrl.hasListener;

  @override
  AdapterPlaybackState state = AdapterPlaybackState.stopped;
  @override
  Future<void> seek({required int positionMs}) async {}
  @override
  set media(String uri) {}
  @override
  Future<void> prepare({int startMs = 0}) async {}
  @override
  int get position => 0;
  @override
  int get duration => 0;
  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo.empty;
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
  void dispose() {}
}

void main() {
  testWidgets('PlayerScreen 销毁时取消全部播放器事件订阅（含 onEvent）',
      (tester) async {
    final player = _FakeStreamingPlayerAdapter();
    PlayerEngineFactory.debugCreateOverride =
        (engine, {erikaOutputMode = ErikaOutputMode.sdr}) => player;
    addTearDown(() => PlayerEngineFactory.debugCreateOverride = null);

    final container = ProviderContainer(
      overrides: [
        settingsProvider
            .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: PlayerScreen(itemId: 'item-x', isHost: false),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.stateCtrl.hasListener, isTrue, reason: '挂载后订阅 onStateChanged');
    expect(player.statusCtrl.hasListener, isTrue, reason: '挂载后订阅 onMediaStatus');
    expect(player.eventCtrl.hasListener, isTrue,
        reason: '挂载后订阅 onEvent（修复前该订阅匿名且从不取消）');

    // 卸载页面触发 State.dispose；再推进假时钟让延迟释放 native player
    // 的 150ms timer 落定，避免 "Timer still pending" 报错。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(player.hasAnyListener, isFalse,
        reason: 'dispose 后必须取消全部事件订阅，不得残留监听');
  });
}

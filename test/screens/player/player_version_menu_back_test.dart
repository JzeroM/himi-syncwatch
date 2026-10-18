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

/// 播放器版本面板的返回键回归（v1.2.24）。
///
/// 真机症状：多版本播放器打开「版本」面板后按返回键，面板不关闭且
/// 焦点不归还版本按钮——`TvBackConfirm.onBack` 的面板互斥列表漏了
/// `_showVersionMenu`（与 v1.1.2xx 其他选择器面板同款收口，647ac50）。
class _FakeStreamingPlayerAdapter implements PlayerAdapter {
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
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => const Stream.empty();
  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => const Stream.empty();
  @override
  Stream<AdapterMediaEvent> get onEvent => const Stream.empty();
  @override
  void dispose() {}
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

Future<ProviderContainer> _pumpPlayer(WidgetTester tester) async {
  _mockPluginChannels(tester);
  final player = _FakeStreamingPlayerAdapter();
  PlayerEngineFactory.debugCreateOverride =
      (engine, {erikaOutputMode = ErikaOutputMode.sdr}) => player;
  addTearDown(() => PlayerEngineFactory.debugCreateOverride = null);

  final item = _multiSourceMovie();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
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
  return container;
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
}

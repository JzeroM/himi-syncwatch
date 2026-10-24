import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/player_core.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart' as himi;

class _FakeCore extends AbstractPlayer
    implements
        MediaStatusPlayer,
        NativeHandlePlayer,
        TextureSizePlayer,
        HttpHeadersPlayer,
        ColorSpacePlayer,
        AudioBackendsPlayer,
        PlayerAsyncDisposable,
        PlayerEventSource {
  @override
  PlayerPlaybackState state = PlayerPlaybackState.paused;

  @override
  double volume = 1.0;

  @override
  double playbackRate = 1.0;

  @override
  String media = '';

  @override
  final ValueNotifier<int?> textureId = ValueNotifier<int?>(7);

  @override
  PlayerMediaInfo mediaInfo = PlayerMediaInfo(
    duration: 1234,
    video: [
      PlayerVideoStreamInfo(
        codec: PlayerVideoCodecParams(width: 1920, height: 1080, name: 'hevc'),
      ),
    ],
    audio: [
      PlayerAudioStreamInfo(
        codec: PlayerAudioCodecParams(
          name: 'aac',
          bitRate: 128000,
          channels: 2,
          sampleRate: 48000,
        ),
        rawRepresentation: 'aac',
      ),
    ],
    subtitle: [
      PlayerSubtitleStreamInfo(
        title: 'PGS',
        codec: 'pgssub',
        streamIndex: 6,
        rawRepresentation: 'pgssub',
      ),
    ],
  );

  @override
  List<int> activeSubtitleTracks = <int>[];

  @override
  List<int> activeAudioTracks = <int>[];

  @override
  int position = 0;

  @override
  int bufferedPosition = 0;

  @override
  PlayerMediaStatus mediaStatus = PlayerMediaStatus.prepared;

  @override
  int nativeHandle = 42;

  @override
  Future<Size?> get textureSize async => const Size(1920, 1080);

  Map<String, String> httpHeaders = const {};

  PlayerColorSpace colorSpace = PlayerColorSpace.unknown;

  List<String> _audioBackends = const [];

  List<String> get audioBackends => _audioBackends;

  @override
  set audioBackends(List<String> value) => _audioBackends = value;

  final _stateCtrl = StreamController<
      ({
        PlayerPlaybackState oldValue,
        PlayerPlaybackState newValue
      })>.broadcast();
  final _statusCtrl = StreamController<
      ({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>.broadcast();
  final _eventCtrl = StreamController<PlayerMediaEvent>.broadcast();

  @override
  Stream<({PlayerPlaybackState oldValue, PlayerPlaybackState newValue})>
      get onStateChanged => _stateCtrl.stream;

  @override
  Stream<({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>
      get onMediaStatus => _statusCtrl.stream;

  @override
  Stream<PlayerMediaEvent> get onEvent => _eventCtrl.stream;

  int? preparedStartMs;
  PlayerMediaType? setMediaType;
  bool disposed = false;

  @override
  bool get supportsExternalSubtitles => true;

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}

  @override
  Future<int?> updateTexture({int? width, int? height, bool? tunnel}) async =>
      7;

  @override
  void setMedia(String path, PlayerMediaType type) {
    media = path;
    setMediaType = type;
  }

  @override
  Future<void> prepare({int startMs = 0}) async {}

  @override
  void seek({required int position}) {
    this.position = position;
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  Future<void> disposeAsync() async {
    disposed = true;
    await _stateCtrl.close();
    await _statusCtrl.close();
    await _eventCtrl.close();
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async =>
      PlayerFrame(width: 2, height: 2, bytes: Uint8List(16));

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}

  @override
  List<String> getDecoders(PlayerMediaType type) => const [];

  @override
  String? getProperty(String key) => null;

  @override
  void setProperty(String key, String value) {}

  @override
  Future<void> playDirectly() async {}

  @override
  Future<void> pauseDirectly() async {}

  @override
  void setPlaybackRate(double rate) => playbackRate = rate;

  @override
  void stepForward() {}

  @override
  void stepBackward() {}

  @override
  void setHttpHeaders(Map<String, String> headers) => httpHeaders = headers;

  @override
  void setColorSpace(PlayerColorSpace colorSpace) =>
      this.colorSpace = colorSpace;
}

class _AsyncSeekFitCore extends _FakeCore
    implements PlayerAsyncSeek, VideoFitPlayer {
  int? awaitedSeekPosition;
  BoxFit? appliedFit;
  Size? appliedContainer;
  Size? appliedVideo;

  @override
  Future<void> seekAndWait({required int position}) async {
    awaitedSeekPosition = position;
    this.position = position;
  }

  @override
  void applyVideoFit(
    BoxFit fit, {
    required Size container,
    required Size video,
  }) {
    appliedFit = fit;
    appliedContainer = container;
    appliedVideo = video;
  }
}

void main() {
  test('PlayerCoreBridge 优先等待异步 seek 并透传视频裁剪', () async {
    final core = _AsyncSeekFitCore();
    final bridge = PlayerCoreBridge(core);

    await bridge.seek(positionMs: 4321);
    expect(core.awaitedSeekPosition, 4321);
    expect(core.position, 4321);

    bridge.applyVideoFit(
      BoxFit.cover,
      container: const Size(2400, 1080),
      video: const Size(1920, 1080),
    );
    expect(core.appliedFit, BoxFit.cover);
    expect(core.appliedContainer, const Size(2400, 1080));
    expect(core.appliedVideo, const Size(1920, 1080));
  });

  test('PlayerCoreBridge 映射状态/媒体/轨道/截图', () async {
    final core = _FakeCore();
    final bridge = PlayerCoreBridge(core);

    expect(bridge.state, himi.AdapterPlaybackState.paused);
    bridge.state = himi.AdapterPlaybackState.playing;
    expect(core.state, PlayerPlaybackState.playing);

    bridge.volume = 0.5;
    bridge.playbackRate = 2.0;
    expect(core.volume, 0.5);
    expect(core.playbackRate, 2.0);

    bridge.media = 'https://example/video';
    expect(core.media, 'https://example/video');

    await bridge.setMedia('sub.srt', type: himi.AdapterMediaType.subtitle);
    expect(core.setMediaType, PlayerMediaType.subtitle);

    core.position = 100;
    expect(bridge.position, 100);
    await bridge.seek(positionMs: 500);
    expect(core.position, 500);

    expect(bridge.mediaInfo.duration, 1234);
    expect(bridge.mediaInfo.video.single.codec, 'hevc');
    expect(bridge.mediaInfo.audio.single.codec, 'aac');
    expect(bridge.mediaInfo.subtitleCount, 1);

    expect(bridge.nativeHandle, 42);
    expect(await bridge.textureSize, const Size(1920, 1080));
    expect(bridge.mediaStatus.rawValue, PlayerMediaStatus.prepared.rawValue);
    expect(await bridge.snapshot(), isNotNull);

    bridge.setHttpHeaders({'X-Emby-Token': 't'});
    expect(core.httpHeaders['X-Emby-Token'], 't');
    bridge.setColorSpace(himi.AdapterColorSpace.bt709);
    expect(core.colorSpace, PlayerColorSpace.bt709);
    bridge.audioBackends = ['aaudio'];
    expect(core.audioBackends, ['aaudio']);

    bridge.activeAudioTracks = [1];
    bridge.activeSubtitleTracks = [2];
    expect(core.activeAudioTracks, [1]);
    expect(core.activeSubtitleTracks, [2]);
  });

  test('PlayerCoreBridge 透传事件与异步释放', () async {
    final core = _FakeCore();
    final bridge = PlayerCoreBridge(core);

    final states = <himi.AdapterPlaybackState>[];
    final statuses = <int>[];
    final events = <String>[];
    final stateSub =
        bridge.onStateChanged.listen((e) => states.add(e.newValue));
    final statusSub =
        bridge.onMediaStatus.listen((e) => statuses.add(e.newValue.rawValue));
    final eventSub = bridge.onEvent.listen((e) => events.add(e.detail));

    core._stateCtrl.add((
      oldValue: PlayerPlaybackState.paused,
      newValue: PlayerPlaybackState.playing,
    ));
    core._statusCtrl.add((
      oldValue: PlayerMediaStatus.prepared,
      newValue: PlayerMediaStatus.end,
    ));
    core._eventCtrl.add(const PlayerMediaEvent(1, 'error', 'boom'));
    await Future<void>.delayed(Duration.zero);

    expect(states, [himi.AdapterPlaybackState.playing]);
    expect(statuses, [PlayerMediaStatus.end.rawValue]);
    expect(events, ['boom']);

    await stateSub.cancel();
    await statusSub.cancel();
    await eventSub.cancel();
    await bridge.disposeAsync();
    expect(core.disposed, isTrue);
  });
}

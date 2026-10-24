import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show ValueListenable;

import '../services/player/player_adapter.dart' as himi;
import 'abstract_player.dart';
import 'player_data_models.dart';
import 'player_enums.dart';

/// 将现有 HIMI [himi.PlayerAdapter] 接到 player_core 的临时适配器。
///
/// 迁移期用它先让默认 MDK 路径走 player_core；后续把各内核替换成
/// NipaPlay 风格实现时，只需替换本类内部实现。
class HimiPlayerCoreAdapter extends AbstractPlayer
    implements
        MediaStatusPlayer,
        NativeHandlePlayer,
        TextureSizePlayer,
        HttpHeadersPlayer,
        ColorSpacePlayer,
        AudioBackendsPlayer,
        RenderVideoPlayer,
        PlayerEventSource,
        PlayerAsyncSetMedia,
        PlayerAsyncDisposable {
  HimiPlayerCoreAdapter(this.delegate) {
    _stateSub = delegate.onStateChanged.listen((e) {
      _stateCtrl.add((
        oldValue: _mapState(e.oldValue),
        newValue: _mapState(e.newValue),
      ));
    });
    _statusSub = delegate.onMediaStatus.listen((e) {
      _statusCtrl.add((
        oldValue: PlayerMediaStatus(e.oldValue.rawValue),
        newValue: PlayerMediaStatus(e.newValue.rawValue),
      ));
    });
    _eventSub = delegate.onEvent.listen((e) {
      _eventCtrl.add(PlayerMediaEvent(e.error, e.category, e.detail));
    });
  }

  final himi.PlayerAdapter delegate;

  final _stateCtrl = StreamController<
      ({
        PlayerPlaybackState oldValue,
        PlayerPlaybackState newValue
      })>.broadcast();
  final _statusCtrl = StreamController<
      ({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>.broadcast();
  final _eventCtrl = StreamController<PlayerMediaEvent>.broadcast();
  StreamSubscription? _stateSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _eventSub;
  bool _disposed = false;

  @override
  PlayerPlaybackState get state => _mapState(delegate.state);

  @override
  set state(PlayerPlaybackState value) => delegate.state = _unmapState(value);

  @override
  Future<void> seek({required int position}) =>
      delegate.seek(positionMs: position);

  String _media = '';

  @override
  set media(String value) {
    _media = value;
    delegate.media = value;
  }

  @override
  String get media => _media;

  @override
  Future<void> prepare({int startMs = 0}) => delegate.prepare(startMs: startMs);

  @override
  int get position => delegate.position;

  @override
  int get bufferedPosition => delegate.buffered();

  @override
  double get volume => delegate.volume;

  @override
  set volume(double value) => delegate.volume = value;

  @override
  double get playbackRate => delegate.playbackRate;

  @override
  set playbackRate(double value) => delegate.playbackRate = value;

  @override
  PlayerMediaInfo get mediaInfo {
    final info = delegate.mediaInfo;
    return PlayerMediaInfo(
      duration: info.duration,
      video: info.video
          .map((v) => PlayerVideoStreamInfo(
                codec: PlayerVideoCodecParams(
                  width: v.width,
                  height: v.height,
                  name: v.codec,
                ),
                codecName: v.codec,
                par: v.par,
                rotation: v.rotation,
                colorSpace: _mapColorSpaceToCore(v.colorSpace),
                doviProfile: v.doviProfile,
                formatName: v.formatName,
                bitRate: v.bitRate,
              ))
          .toList(),
      audio: info.audio
          .map((a) => PlayerAudioStreamInfo(
                codec: PlayerAudioCodecParams(
                  name: a.codec,
                  bitRate: a.bitRate,
                  channels: a.channels,
                  sampleRate: a.sampleRate,
                ),
                rawRepresentation: a.codec,
              ))
          .toList(),
      subtitle: List<PlayerSubtitleStreamInfo>.generate(
        info.subtitleCount,
        (i) => PlayerSubtitleStreamInfo(
          title: 'Subtitle ${i + 1}',
          rawRepresentation: '',
        ),
      ),
    );
  }

  @override
  List<int> get activeSubtitleTracks => delegate.activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) =>
      delegate.activeSubtitleTracks = value;

  @override
  List<int> get activeAudioTracks => delegate.activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) => delegate.activeAudioTracks = value;

  @override
  bool get supportsExternalSubtitles => true;

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) =>
      delegate.setBufferRange(min: minMs, max: maxMs, drop: drop);

  @override
  ValueListenable<int?> get textureId => delegate.textureId;

  @override
  int get nativeHandle => delegate.nativeHandle;

  @override
  Future<Size?> get textureSize => delegate.textureSize;

  @override
  Future<int?> updateTexture({int? width, int? height, bool? tunnel}) =>
      delegate.updateTexture(width: width, height: height, tunnel: tunnel);

  @override
  void renderVideo() => delegate.renderVideo();

  @override
  void setMedia(String path, PlayerMediaType type) {
    unawaited(setMediaAsync(path, type));
  }

  @override
  Future<void> setMediaAsync(String path, PlayerMediaType type) =>
      delegate.setMedia(
        path,
        type: switch (type) {
          PlayerMediaType.audio => himi.AdapterMediaType.audio,
          PlayerMediaType.subtitle => himi.AdapterMediaType.subtitle,
          _ => himi.AdapterMediaType.subtitle,
        },
      );

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final bytes = await delegate.snapshot(
      width: width > 0 ? width : null,
      height: height > 0 ? height : null,
    );
    if (bytes == null) return null;
    return PlayerFrame(width: width, height: height, bytes: bytes);
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    if (type == PlayerMediaType.audio) {
      delegate.audioDecoders = decoders;
    } else if (type == PlayerMediaType.video) {
      delegate.videoDecoders = decoders;
    }
  }

  @override
  List<String> getDecoders(PlayerMediaType type) => switch (type) {
        PlayerMediaType.audio => delegate.audioDecoders,
        PlayerMediaType.video => delegate.videoDecoders,
        _ => const [],
      };

  @override
  String? getProperty(String key) => delegate.getProperty(key);

  @override
  void setProperty(String key, String value) =>
      delegate.setProperty(key, value);

  @override
  void setHttpHeaders(Map<String, String> headers) =>
      delegate.setHttpHeaders(headers);

  @override
  void setColorSpace(PlayerColorSpace colorSpace) =>
      delegate.setColorSpace(_mapColorSpace(colorSpace));

  @override
  set audioBackends(List<String> backends) => delegate.audioBackends = backends;

  @override
  PlayerMediaStatus get mediaStatus =>
      PlayerMediaStatus(delegate.mediaStatus.rawValue);

  @override
  Stream<({PlayerPlaybackState oldValue, PlayerPlaybackState newValue})>
      get onStateChanged => _stateCtrl.stream;

  @override
  Stream<({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>
      get onMediaStatus => _statusCtrl.stream;

  @override
  Stream<PlayerMediaEvent> get onEvent => _eventCtrl.stream;

  @override
  Future<void> playDirectly() async =>
      delegate.state = himi.AdapterPlaybackState.playing;

  @override
  Future<void> pauseDirectly() async =>
      delegate.state = himi.AdapterPlaybackState.paused;

  @override
  void setPlaybackRate(double rate) => delegate.playbackRate = rate;

  @override
  void stepForward() {}

  @override
  void stepBackward() {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_stateSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_eventSub?.cancel());
    delegate.dispose();
    unawaited(_stateCtrl.close());
    unawaited(_statusCtrl.close());
    unawaited(_eventCtrl.close());
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSub?.cancel();
    await _statusSub?.cancel();
    await _eventSub?.cancel();
    if (delegate is himi.AsyncDisposablePlayer) {
      await (delegate as himi.AsyncDisposablePlayer).disposeAsync();
    } else {
      delegate.dispose();
    }
    await _stateCtrl.close();
    await _statusCtrl.close();
    await _eventCtrl.close();
  }

  static PlayerPlaybackState _mapState(himi.AdapterPlaybackState s) =>
      switch (s) {
        himi.AdapterPlaybackState.playing => PlayerPlaybackState.playing,
        himi.AdapterPlaybackState.paused => PlayerPlaybackState.paused,
        himi.AdapterPlaybackState.stopped => PlayerPlaybackState.stopped,
      };

  static himi.AdapterPlaybackState _unmapState(PlayerPlaybackState s) =>
      switch (s) {
        PlayerPlaybackState.playing => himi.AdapterPlaybackState.playing,
        PlayerPlaybackState.paused => himi.AdapterPlaybackState.paused,
        PlayerPlaybackState.stopped => himi.AdapterPlaybackState.stopped,
      };

  static PlayerColorSpace _mapColorSpaceToCore(himi.AdapterColorSpace cs) =>
      switch (cs) {
        himi.AdapterColorSpace.bt709 => PlayerColorSpace.bt709,
        himi.AdapterColorSpace.bt2100PQ => PlayerColorSpace.bt2100PQ,
        himi.AdapterColorSpace.bt2100hlg => PlayerColorSpace.bt2100hlg,
        himi.AdapterColorSpace.unknown => PlayerColorSpace.unknown,
      };

  static himi.AdapterColorSpace _mapColorSpace(PlayerColorSpace cs) =>
      switch (cs) {
        PlayerColorSpace.bt709 => himi.AdapterColorSpace.bt709,
        PlayerColorSpace.bt2100PQ => himi.AdapterColorSpace.bt2100PQ,
        PlayerColorSpace.bt2100hlg => himi.AdapterColorSpace.bt2100hlg,
        PlayerColorSpace.unknown => himi.AdapterColorSpace.unknown,
      };
}

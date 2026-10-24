import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;

import 'package:erika_flutter/erika_flutter.dart' show ErikaPlayer;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:media_kit_video/media_kit_video.dart' show VideoController;

import '../services/player/erika_player_adapter.dart';
import '../services/player/media_kit_player_adapter.dart';
import '../services/player/player_adapter.dart' as himi;
import 'abstract_player.dart';
import 'himi_player_core_adapter.dart';
import 'player_data_models.dart';
import 'player_enums.dart';

/// 把 NipaPlay 风格的 [AbstractPlayer] 适配成 HIMI 播放页使用的
/// [himi.PlayerAdapter]。HIMI UI 不需要直接依赖 player_core。
class PlayerCoreBridge
    implements
        himi.PlayerAdapter,
        himi.AsyncDisposablePlayer,
        himi.ErikaPlayerProvider,
        himi.MediaKitPlayerProvider,
        himi.MediaKitSettingsApplier,
        himi.MediaKitVideoFitApplier,
        himi.ErikaDanmakuPlayer {
  PlayerCoreBridge(this.core);

  final AbstractPlayer core;

  /// 迁移期访问底层 HIMI adapter（Erika 原生 view / media_kit controller）。
  himi.PlayerAdapter? get wrappedAdapter => core is HimiPlayerCoreAdapter
      ? (core as HimiPlayerCoreAdapter).delegate
      : null;

  T? wrappedAs<T extends himi.PlayerAdapter>() {
    final adapter = wrappedAdapter;
    return adapter is T ? adapter : null;
  }

  @override
  himi.AdapterPlaybackState get state => _mapState(core.state);

  @override
  set state(himi.AdapterPlaybackState value) {
    core.state = _unmapState(value);
  }

  @override
  Future<void> seek({required int positionMs}) async {
    final core = this.core;
    if (core is PlayerAsyncSeek) {
      await (core as PlayerAsyncSeek).seekAndWait(position: positionMs);
    } else {
      core.seek(position: positionMs);
    }
  }

  @override
  void applyVideoFit(
    BoxFit fit, {
    required Size container,
    required Size video,
  }) {
    final core = this.core;
    if (core is VideoFitPlayer) {
      (core as VideoFitPlayer)
          .applyVideoFit(fit, container: container, video: video);
    }
  }

  @override
  set media(String uri) => core.media = uri;

  @override
  Future<void> prepare({int startMs = 0}) async {
    await core.prepare(startMs: startMs);
  }

  @override
  int get position => core.position;

  @override
  int get duration => core.mediaInfo.duration;

  @override
  himi.AdapterMediaInfo get mediaInfo {
    final info = core.mediaInfo;
    return himi.AdapterMediaInfo(
      duration: info.duration,
      audio: (info.audio ?? const <PlayerAudioStreamInfo>[])
          .map((a) => himi.AdapterAudioStream(
                codec: a.codec.name ?? '',
                bitRate: a.codec.bitRate ?? 0,
                channels: a.codec.channels ?? 0,
                sampleRate: a.codec.sampleRate ?? 0,
              ))
          .toList(),
      video: (info.video ?? const <PlayerVideoStreamInfo>[])
          .map((v) => himi.AdapterVideoStream(
                codec: v.codec.name ?? v.codecName ?? '',
                width: v.codec.width,
                height: v.codec.height,
                par: v.par,
                rotation: v.rotation,
                colorSpace: _toHimiColorSpace(v.colorSpace),
                doviProfile: v.doviProfile,
                formatName: v.formatName,
                bitRate: v.bitRate,
              ))
          .toList(),
      subtitleCount: info.subtitle?.length ?? 0,
    );
  }

  @override
  double get volume => core.volume;

  @override
  set volume(double value) => core.volume = value;

  @override
  double get playbackRate => core.playbackRate;

  @override
  set playbackRate(double value) => core.playbackRate = value;

  @override
  himi.AdapterMediaStatus get mediaStatus {
    final status = core is MediaStatusPlayer
        ? (core as MediaStatusPlayer).mediaStatus
        : _deriveStatus();
    return himi.AdapterMediaStatus(status.rawValue);
  }

  @override
  int buffered() => core.bufferedPosition;

  @override
  ValueListenable<int?> get textureId => core.textureId;

  @override
  int get nativeHandle => core is NativeHandlePlayer
      ? (core as NativeHandlePlayer).nativeHandle
      : 0;

  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) async =>
      await core.updateTexture(width: width, height: height, tunnel: tunnel) ??
      -1;

  @override
  Future<Size?> get textureSize async => core is TextureSizePlayer
      ? (core as TextureSizePlayer).textureSize
      : null;

  @override
  void setColorSpace(himi.AdapterColorSpace cs) {
    if (core is ColorSpacePlayer) {
      (core as ColorSpacePlayer).setColorSpace(_mapColorSpace(cs));
    }
  }

  @override
  void renderVideo() {
    if (core is RenderVideoPlayer) {
      (core as RenderVideoPlayer).renderVideo();
    }
  }

  @override
  List<int> get activeAudioTracks => core.activeAudioTracks;

  @override
  set activeAudioTracks(List<int> tracks) => core.activeAudioTracks = tracks;

  @override
  List<int> get activeSubtitleTracks => core.activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> tracks) =>
      core.activeSubtitleTracks = tracks;

  @override
  Stream<
      ({
        himi.AdapterPlaybackState oldValue,
        himi.AdapterPlaybackState newValue
      })> get onStateChanged {
    if (core is! PlayerEventSource) return const Stream.empty();
    return (core as PlayerEventSource).onStateChanged.map((e) => (
          oldValue: _mapState(e.oldValue),
          newValue: _mapState(e.newValue),
        ));
  }

  @override
  Stream<({himi.AdapterMediaStatus oldValue, himi.AdapterMediaStatus newValue})>
      get onMediaStatus {
    if (core is! PlayerEventSource) return const Stream.empty();
    return (core as PlayerEventSource).onMediaStatus.map((e) => (
          oldValue: himi.AdapterMediaStatus(e.oldValue.rawValue),
          newValue: himi.AdapterMediaStatus(e.newValue.rawValue),
        ));
  }

  @override
  Stream<himi.AdapterMediaEvent> get onEvent {
    if (core is! PlayerEventSource) return const Stream.empty();
    return (core as PlayerEventSource).onEvent.map(
          (e) => himi.AdapterMediaEvent(e.error, e.category, e.detail),
        );
  }

  @override
  void setProperty(String name, String value) => core.setProperty(name, value);

  @override
  String? getProperty(String name) => core.getProperty(name);

  @override
  void setHttpHeaders(Map<String, String> headers) {
    if (core is HttpHeadersPlayer) {
      (core as HttpHeadersPlayer).setHttpHeaders(headers);
    }
  }

  @override
  List<String> get videoDecoders => core.getDecoders(PlayerMediaType.video);

  @override
  set videoDecoders(List<String> decoders) =>
      core.setDecoders(PlayerMediaType.video, decoders);

  @override
  List<String> get audioDecoders => core.getDecoders(PlayerMediaType.audio);

  @override
  set audioDecoders(List<String> decoders) =>
      core.setDecoders(PlayerMediaType.audio, decoders);

  @override
  set audioBackends(List<String> backends) {
    if (core is AudioBackendsPlayer) {
      (core as AudioBackendsPlayer).audioBackends = backends;
    }
  }

  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) =>
      core.setBufferRange(minMs: min, maxMs: max, drop: drop);

  @override
  Future<void> setMedia(String uri,
      {required himi.AdapterMediaType type}) async {
    core.setMedia(uri, _unmapMediaType(type));
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) async {
    final frame = await core.snapshot(
      width: width ?? 0,
      height: height ?? 0,
    );
    return frame?.bytes;
  }

  @override
  ErikaPlayer? get erikaPlayer {
    if (core is ErikaViewPlayer) {
      final value = (core as ErikaViewPlayer).erikaPlayer;
      return value is ErikaPlayer ? value : null;
    }
    return wrappedAs<ErikaPlayerAdapter>()?.erikaPlayer;
  }

  @override
  VideoController? get mediaKitController {
    if (core is MediaKitViewPlayer) {
      final value = (core as MediaKitViewPlayer).mediaKitController;
      return value is VideoController ? value : null;
    }
    return wrappedAs<MediaKitPlayerAdapter>()?.videoController;
  }

  @override
  Future<void> applyMediaKitSettings({
    String? hwdec,
    String? toneMapping,
    double? cacheSizeMb,
  }) async {
    if (core is MediaKitSettingsPlayer) {
      (core as MediaKitSettingsPlayer).applyMediaKitSettings(
        hwdec: hwdec,
        toneMapping: toneMapping,
        cacheSizeMb: cacheSizeMb,
      );
      return;
    }
    final wrapped = wrappedAs<MediaKitPlayerAdapter>();
    if (wrapped != null) {
      wrapped.applySettings(
        hwdec: hwdec ?? 'auto-safe',
        toneMapping: toneMapping ?? 'auto',
        cacheSizeMb: cacheSizeMb ?? 150,
      );
    }
  }

  @override
  Future<void> loadDanmakuJsonString(String json) async {
    if (core is ErikaDanmakuCapable) {
      await (core as ErikaDanmakuCapable).loadDanmakuJsonString(json);
    }
  }

  @override
  Future<void> setDanmakuEnabled(bool enabled) async {
    if (core is ErikaDanmakuCapable) {
      await (core as ErikaDanmakuCapable).setDanmakuEnabled(enabled);
    }
  }

  @override
  Future<void> setDanmakuConfigHimi({
    double? fontSize,
    double? opacity,
    double? scrollDurationSeconds,
    double? displayArea,
    int? maxLinesPerMode,
    int? maxQuantity,
    bool? blockTop,
    bool? blockBottom,
    bool? blockScroll,
    List<String>? blockWords,
  }) async {
    if (core is ErikaDanmakuCapable) {
      await (core as ErikaDanmakuCapable).setDanmakuConfigHimi(
        fontSize: fontSize,
        opacity: opacity,
        scrollDurationSeconds: scrollDurationSeconds,
        displayArea: displayArea,
        maxLinesPerMode: maxLinesPerMode,
        maxQuantity: maxQuantity,
        blockTop: blockTop,
        blockBottom: blockBottom,
        blockScroll: blockScroll,
        blockWords: blockWords,
      );
    }
  }

  @override
  void dispose() => core.dispose();

  @override
  Future<void> disposeAsync() async {
    if (core is PlayerAsyncDisposable) {
      await (core as PlayerAsyncDisposable).disposeAsync();
    } else {
      core.dispose();
    }
  }

  PlayerMediaStatus _deriveStatus() {
    if (core.state == PlayerPlaybackState.playing) {
      return PlayerMediaStatus.loaded;
    }
    if (core.state == PlayerPlaybackState.paused) {
      return PlayerMediaStatus.prepared;
    }
    return PlayerMediaStatus.unloaded;
  }

  static himi.AdapterPlaybackState _mapState(PlayerPlaybackState s) =>
      switch (s) {
        PlayerPlaybackState.playing => himi.AdapterPlaybackState.playing,
        PlayerPlaybackState.paused => himi.AdapterPlaybackState.paused,
        PlayerPlaybackState.stopped => himi.AdapterPlaybackState.stopped,
      };

  static PlayerPlaybackState _unmapState(himi.AdapterPlaybackState s) =>
      switch (s) {
        himi.AdapterPlaybackState.playing => PlayerPlaybackState.playing,
        himi.AdapterPlaybackState.paused => PlayerPlaybackState.paused,
        himi.AdapterPlaybackState.stopped => PlayerPlaybackState.stopped,
      };

  static PlayerMediaType _unmapMediaType(himi.AdapterMediaType type) =>
      switch (type) {
        himi.AdapterMediaType.audio => PlayerMediaType.audio,
        himi.AdapterMediaType.subtitle => PlayerMediaType.subtitle,
      };

  static himi.AdapterColorSpace _toHimiColorSpace(PlayerColorSpace cs) =>
      switch (cs) {
        PlayerColorSpace.bt709 => himi.AdapterColorSpace.bt709,
        PlayerColorSpace.bt2100PQ => himi.AdapterColorSpace.bt2100PQ,
        PlayerColorSpace.bt2100hlg => himi.AdapterColorSpace.bt2100hlg,
        PlayerColorSpace.unknown => himi.AdapterColorSpace.unknown,
      };

  static PlayerColorSpace _mapColorSpace(himi.AdapterColorSpace cs) =>
      switch (cs) {
        himi.AdapterColorSpace.bt709 => PlayerColorSpace.bt709,
        himi.AdapterColorSpace.bt2100PQ => PlayerColorSpace.bt2100PQ,
        himi.AdapterColorSpace.bt2100hlg => PlayerColorSpace.bt2100hlg,
        himi.AdapterColorSpace.unknown => PlayerColorSpace.unknown,
      };
}

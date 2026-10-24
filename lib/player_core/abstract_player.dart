import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;

import 'package:flutter/foundation.dart' show ValueListenable;

import 'player_data_models.dart';
import 'player_enums.dart';

const int networkMediaLoadMaxAttempts = 5;

abstract interface class PlayerAsyncDisposable {
  Future<void> disposeAsync();
}

abstract interface class PlayerAsyncSeek {
  Future<void> seekAndWait({required int position});
}

abstract interface class PlayerBufferingAware {
  ValueListenable<bool> get buffering;
}

abstract interface class MediaStatusPlayer {
  PlayerMediaStatus get mediaStatus;
}

abstract interface class PlayerAsyncExternalSubtitle {
  Future<void> setExternalSubtitleAsync(String path);
}

abstract interface class PlayerAsyncSetMedia {
  Future<void> setMediaAsync(String path, PlayerMediaType type);
}

abstract interface class PlayerMediaLoadAware {
  bool get isMediaReady;
  bool get hasReceivedRealPosition;
  bool get hasMediaLoadFailed;
  String? get mediaLoadError;

  Future<bool> waitUntilMediaReady({required Duration timeout});
  Future<bool> retryCurrentMediaLoad();
}

enum PlayerGifExportQuality { normal, high }

class PlayerGifExportRequest {
  const PlayerGifExportRequest({
    required this.inputUri,
    required this.outputPath,
    required this.start,
    required this.end,
    required this.framesPerSecond,
    required this.outputWidth,
    required this.outputHeight,
    this.quality = PlayerGifExportQuality.normal,
    this.httpHeaders = const <String, String>{},
  });

  final String inputUri;
  final String outputPath;
  final Duration start;
  final Duration end;
  final int framesPerSecond;
  final int outputWidth;
  final int outputHeight;
  final PlayerGifExportQuality quality;
  final Map<String, String> httpHeaders;
}

class PlayerGifExportResult {
  const PlayerGifExportResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.fileSize,
  });

  final String outputPath;
  final int width;
  final int height;
  final int frameCount;
  final int fileSize;
}

abstract interface class PlayerGifExportCapable {
  bool get supportsGifExport;
  Future<PlayerGifExportResult> exportGif(PlayerGifExportRequest request);
}

/// 引擎无关事件源。HIMI 播放页依赖这三条流。
abstract interface class PlayerEventSource {
  Stream<({PlayerPlaybackState oldValue, PlayerPlaybackState newValue})>
      get onStateChanged;
  Stream<({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>
      get onMediaStatus;
  Stream<PlayerMediaEvent> get onEvent;
}

abstract interface class NativeHandlePlayer {
  int get nativeHandle;
}

abstract interface class TextureSizePlayer {
  Future<Size?> get textureSize;
}

abstract interface class HttpHeadersPlayer {
  void setHttpHeaders(Map<String, String> headers);
}

abstract interface class ColorSpacePlayer {
  void setColorSpace(PlayerColorSpace colorSpace);
}

abstract interface class AudioBackendsPlayer {
  set audioBackends(List<String> backends);
}

abstract interface class RenderVideoPlayer {
  void renderVideo();
}

abstract interface class ErikaViewPlayer {
  Object get erikaPlayer;
}

abstract interface class MediaKitViewPlayer {
  Object? get mediaKitController;
}

abstract interface class VideoFitPlayer {
  void applyVideoFit(
    BoxFit fit, {
    required Size container,
    required Size video,
  });
}

abstract interface class MediaKitSettingsPlayer {
  void applyMediaKitSettings({
    String? hwdec,
    String? toneMapping,
    double? cacheSizeMb,
  });
}

abstract interface class ErikaDanmakuCapable {
  Future<void> loadDanmakuJsonString(String json);
  Future<void> setDanmakuEnabled(bool enabled);
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
  });
}

abstract class AbstractPlayer {
  double get volume;
  set volume(double value);

  double get playbackRate;
  set playbackRate(double value);

  PlayerPlaybackState get state;
  set state(PlayerPlaybackState value);

  ValueListenable<int?> get textureId;

  String get media;
  set media(String value);

  PlayerMediaInfo get mediaInfo;

  List<int> get activeSubtitleTracks;
  set activeSubtitleTracks(List<int> value);

  List<int> get activeAudioTracks;
  set activeAudioTracks(List<int> value);

  int get position;
  int get bufferedPosition;

  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false});

  bool get supportsExternalSubtitles;

  Future<int?> updateTexture({int? width, int? height, bool? tunnel});

  void setMedia(String path, PlayerMediaType type);

  Future<void> prepare({int startMs = 0});

  void seek({required int position});

  void dispose();

  Future<PlayerFrame?> snapshot({int width = 0, int height = 0});

  void setDecoders(PlayerMediaType type, List<String> decoders);
  List<String> getDecoders(PlayerMediaType type);
  String? getProperty(String key);
  void setProperty(String key, String value);

  void setUserAgent(String ua) {}
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {}
  Future<void> setChapter(int index) async {}

  Future<void> playDirectly();
  Future<void> pauseDirectly();
  void setPlaybackRate(double rate);
  void stepForward();
  void stepBackward();
}

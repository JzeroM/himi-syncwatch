import 'player_enums.dart';

import 'dart:typed_data';

enum PlayerErikaAndroidOutputMode { sdr, extendedLinearHdr }

enum PlayerUpscalerMode {
  off,
  erikaArtCnnC4F16,
  erikaArtCnnC4F32,
  erikaArtCnnC4F16Ds,
}

enum PlayerUpscalerBackendStatus {
  off,
  inactive,
  building,
  scalar,
  simdgroupMatrix,
  unknown,
}

class PlayerUpscalerStatus {
  const PlayerUpscalerStatus({
    required this.requestedMode,
    required this.activeBackend,
    required this.fallbackCount,
    required this.upscaledFrames,
    required this.lastEncodeDuration,
    required this.lastGpuDuration,
  });

  const PlayerUpscalerStatus.off()
      : requestedMode = PlayerUpscalerMode.off,
        activeBackend = PlayerUpscalerBackendStatus.off,
        fallbackCount = 0,
        upscaledFrames = 0,
        lastEncodeDuration = Duration.zero,
        lastGpuDuration = Duration.zero;

  final PlayerUpscalerMode requestedMode;
  final PlayerUpscalerBackendStatus activeBackend;
  final int fallbackCount;
  final int upscaledFrames;
  final Duration lastEncodeDuration;
  final Duration lastGpuDuration;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'requestedMode': requestedMode.name,
        'activeBackend': activeBackend.name,
        'fallbackCount': fallbackCount,
        'upscaledFrames': upscaledFrames,
        'lastEncodeMicros': lastEncodeDuration.inMicroseconds,
        'lastGpuMicros': lastGpuDuration.inMicroseconds,
      };
}

class PlayerFrame {
  PlayerFrame({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

class PlayerVideoCodecParams {
  PlayerVideoCodecParams({
    required this.width,
    required this.height,
    this.name,
  });

  final int width;
  final int height;
  final String? name;
}

class PlayerVideoStreamInfo {
  PlayerVideoStreamInfo({
    required this.codec,
    this.codecName,
    this.par = 1.0,
    this.rotation = 0,
    this.colorSpace = PlayerColorSpace.unknown,
    this.doviProfile = 0,
    this.formatName = '',
    this.bitRate = 0,
  });

  final PlayerVideoCodecParams codec;
  final String? codecName;
  final double par;
  final int rotation;
  final PlayerColorSpace colorSpace;
  final int doviProfile;
  final String formatName;
  final int bitRate;
}

class PlayerSubtitleStreamInfo {
  PlayerSubtitleStreamInfo({
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
    this.codec,
    this.isExternal = false,
    this.streamIndex,
  });

  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation;

  /// 字幕 codec（如 pgssub / ass / subrip）；HIMI 用它判断位图字幕。
  final String? codec;
  final bool isExternal;
  final int? streamIndex;

  @override
  String toString() => rawRepresentation;
}

class PlayerAudioCodecParams {
  PlayerAudioCodecParams({
    this.name,
    this.bitRate,
    this.channels,
    this.sampleRate,
  });

  final String? name;
  final int? bitRate;
  final int? channels;
  final int? sampleRate;
}

class PlayerAudioStreamInfo {
  PlayerAudioStreamInfo({
    required this.codec,
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
    this.isExternal = false,
  });

  final PlayerAudioCodecParams codec;
  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation;
  final bool isExternal;

  @override
  String toString() => rawRepresentation;
}

class PlayerChapter {
  const PlayerChapter({
    required this.index,
    required this.startMs,
    required this.title,
  });

  final int index;
  final int startMs;
  final String title;

  @override
  String toString() => 'PlayerChapter(#$index $startMs ms "$title")';
}

class PlayerMediaInfo {
  PlayerMediaInfo({
    required this.duration,
    this.video,
    this.audio,
    this.subtitle,
    this.chapters,
    this.specificErrorMessage,
  });

  final int duration;
  final List<PlayerVideoStreamInfo>? video;
  final List<PlayerAudioStreamInfo>? audio;
  final List<PlayerSubtitleStreamInfo>? subtitle;
  final List<PlayerChapter>? chapters;
  final String? specificErrorMessage;

  PlayerMediaInfo copyWith({
    int? duration,
    List<PlayerVideoStreamInfo>? video,
    List<PlayerAudioStreamInfo>? audio,
    List<PlayerSubtitleStreamInfo>? subtitle,
    List<PlayerChapter>? chapters,
    String? specificErrorMessage,
  }) =>
      PlayerMediaInfo(
        duration: duration ?? this.duration,
        video: video ?? this.video,
        audio: audio ?? this.audio,
        subtitle: subtitle ?? this.subtitle,
        chapters: chapters ?? this.chapters,
        specificErrorMessage: specificErrorMessage ?? this.specificErrorMessage,
      );
}

/// 与 HIMI `AdapterMediaStatus` 使用同一组位值，桥接层可无损映射。
class PlayerMediaStatus {
  const PlayerMediaStatus(this.rawValue);

  static const unloaded = PlayerMediaStatus(0x01);
  static const loading = PlayerMediaStatus(0x02);
  static const loaded = PlayerMediaStatus(0x04);
  static const prepared = PlayerMediaStatus(0x08);
  static const stalled = PlayerMediaStatus(0x10);
  static const buffering = PlayerMediaStatus(0x20);
  static const buffered = PlayerMediaStatus(0x40);
  static const end = PlayerMediaStatus(0x80);
  static const seeking = PlayerMediaStatus(0x100);
  static const invalid = PlayerMediaStatus(0x200);

  final int rawValue;

  bool test(PlayerMediaStatus other) => rawValue & other.rawValue != 0;
  bool get isBuffering => test(buffering);
  bool get isEnd => test(end);

  PlayerMediaStatus operator |(PlayerMediaStatus other) =>
      PlayerMediaStatus(rawValue | other.rawValue);

  @override
  bool operator ==(Object other) =>
      other is PlayerMediaStatus && other.rawValue == rawValue;

  @override
  int get hashCode => rawValue.hashCode;
}

class PlayerMediaEvent {
  const PlayerMediaEvent(this.error, this.category, this.detail);

  final int error;
  final String category;
  final String detail;
}

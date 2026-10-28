import 'package:flutter/foundation.dart' show listEquals;

/// 原生播放器（Surface 模式）的字幕样式快照。
class NativeSubtitleStyle {
  const NativeSubtitleStyle({
    this.fontSize = 16.0,
    this.opacity = 1.0,
    this.textColor = '#FFFFFF',
    this.backgroundColor = '#80000000',
  });

  final double fontSize;
  final double opacity;
  final String textColor;
  final String backgroundColor;

  factory NativeSubtitleStyle.fromJson(Map<Object?, Object?> json) {
    return NativeSubtitleStyle(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      textColor: json['textColor'] as String? ?? '#FFFFFF',
      backgroundColor: json['backgroundColor'] as String? ?? '#80000000',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'fontSize': fontSize,
        'opacity': opacity,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
      };

  NativeSubtitleStyle copyWith({
    double? fontSize,
    double? opacity,
    String? textColor,
    String? backgroundColor,
  }) =>
      NativeSubtitleStyle(
        fontSize: fontSize ?? this.fontSize,
        opacity: opacity ?? this.opacity,
        textColor: textColor ?? this.textColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );

  @override
  bool operator ==(Object other) =>
      other is NativeSubtitleStyle &&
      other.fontSize == fontSize &&
      other.opacity == opacity &&
      other.textColor == textColor &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode =>
      Object.hash(fontSize, opacity, textColor, backgroundColor);
}

/// 音轨/字幕轨快照（来自 mpv `track-list`）。
class NativeTrack {
  const NativeTrack({
    required this.id,
    required this.type,
    this.title,
    this.lang,
    this.selected = false,
  });

  /// mpv 轨道 id（aid/sid）。
  final int id;

  /// audio / sub / video。
  final String type;
  final String? title;
  final String? lang;
  final bool selected;

  factory NativeTrack.fromJson(Map<Object?, Object?> json) => NativeTrack(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'audio',
        title: json['title'] as String?,
        lang: json['lang'] as String?,
        selected: json['selected'] == true,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'title': title,
        'lang': lang,
        'selected': selected,
      };

  @override
  bool operator ==(Object other) =>
      other is NativeTrack &&
      other.id == id &&
      other.type == type &&
      other.title == title &&
      other.lang == lang &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(id, type, title, lang, selected);
}

/// 选集快照。
class NativeEpisode {
  const NativeEpisode({required this.index, required this.title});

  final int index;
  final String title;

  factory NativeEpisode.fromJson(Map<Object?, Object?> json) => NativeEpisode(
        index: (json['index'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
      );

  Map<String, Object?> toJson() =>
      <String, Object?>{'index': index, 'title': title};

  @override
  bool operator ==(Object other) =>
      other is NativeEpisode && other.index == index && other.title == title;

  @override
  int get hashCode => Object.hash(index, title);
}

/// 版本（线路）快照。
class NativeVersion {
  const NativeVersion({required this.index, required this.title});

  final int index;
  final String title;

  factory NativeVersion.fromJson(Map<Object?, Object?> json) => NativeVersion(
        index: (json['index'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
      );

  Map<String, Object?> toJson() =>
      <String, Object?>{'index': index, 'title': title};

  @override
  bool operator ==(Object other) =>
      other is NativeVersion && other.index == index && other.title == title;

  @override
  int get hashCode => Object.hash(index, title);
}

/// 弹幕条目（时间轴分片推送，原生按 positionMs 本地调度）。
class NativeDanmakuItem {
  const NativeDanmakuItem({
    required this.timeMs,
    required this.text,
    this.mode = 'scroll',
    this.color = '#FFFFFF',
  });

  final int timeMs;
  final String text;

  /// scroll / top / bottom。
  final String mode;
  final String color;

  factory NativeDanmakuItem.fromJson(Map<Object?, Object?> json) =>
      NativeDanmakuItem(
        timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        mode: json['mode'] as String? ?? 'scroll',
        color: json['color'] as String? ?? '#FFFFFF',
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'timeMs': timeMs,
        'text': text,
        'mode': mode,
        'color': color,
      };

  @override
  bool operator ==(Object other) =>
      other is NativeDanmakuItem &&
      other.timeMs == timeMs &&
      other.text == text &&
      other.mode == mode &&
      other.color == color;

  @override
  int get hashCode => Object.hash(timeMs, text, mode, color);
}

/// 房间成员快照。
class NativeRoomMember {
  const NativeRoomMember({
    required this.name,
    this.isHost = false,
    this.online = true,
  });

  final String name;
  final bool isHost;
  final bool online;

  factory NativeRoomMember.fromJson(Map<Object?, Object?> json) =>
      NativeRoomMember(
        name: json['name'] as String? ?? '',
        isHost: json['isHost'] == true,
        online: json['online'] != false,
      );

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'isHost': isHost, 'online': online};

  @override
  bool operator ==(Object other) =>
      other is NativeRoomMember &&
      other.name == name &&
      other.isHost == isHost &&
      other.online == online;

  @override
  int get hashCode => Object.hash(name, isHost, online);
}

/// 房间聊天快照。
class NativeRoomChat {
  const NativeRoomChat({required this.name, required this.text, this.timeMs = 0});

  final String name;
  final String text;
  final int timeMs;

  factory NativeRoomChat.fromJson(Map<Object?, Object?> json) => NativeRoomChat(
        name: json['name'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'text': text, 'timeMs': timeMs};

  @override
  bool operator ==(Object other) =>
      other is NativeRoomChat &&
      other.name == name &&
      other.text == text &&
      other.timeMs == timeMs;

  @override
  int get hashCode => Object.hash(name, text, timeMs);
}

/// 推送给原生 UI 的完整播放器状态快照。
///
/// Dart 是唯一权威状态源：原生每次收到快照后覆盖本地状态，并对
/// `positionMs` 做本地插值（播放中按 speed 外推，暂停保持不变）。
class NativePlayerState {
  const NativePlayerState({
    this.engine = 'mpv',
    this.videoOutputRequested = 'surface',
    this.videoOutputActual = 'surface',
    this.nativeSurface = true,
    this.textureId = 0,
    this.hdrOutput = false,
    this.displayHdr = false,
    this.targetTrc = 'auto',
    this.voConfigured,
    this.currentVo,
    this.hwdecCurrent,
    this.surfaceAttached = false,
    this.surfaceId,
    this.surfaceError,
    this.surfaceWidth = 0,
    this.surfaceHeight = 0,
    this.positionMs = 0,
    this.durationMs = 0,
    this.bufferedMs = 0,
    this.paused = true,
    this.buffering = false,
    this.ended = false,
    this.volume = 1.0,
    this.speed = 1.0,
    this.title,
    this.mediaTitle,
    this.videoParams,
    this.audioParams,
    this.tracks = const <NativeTrack>[],
    this.selectedAudioId = 0,
    this.selectedSubtitleId = 0,
    this.subtitleDelayMs = 0,
    this.subtitleStyle = const NativeSubtitleStyle(),
    this.episodes = const <NativeEpisode>[],
    this.currentEpisodeIndex = 0,
    this.versions = const <NativeVersion>[],
    this.currentVersionIndex = 0,
    this.danmakuEnabled = false,
    this.danmakuOpacity = 1.0,
    this.danmakuFontSize = 16.0,
    this.danmakuSpeed = 1.0,
    this.danmakuArea = 'scroll',
    this.danmakuBlockWords = const <String>[],
    this.danmakuItems = const <NativeDanmakuItem>[],
    this.roomCode,
    this.isHost = false,
    this.roomMembers = const <NativeRoomMember>[],
    this.roomChat = const <NativeRoomChat>[],
    this.roomSyncState = 'idle',
    this.segmentIntroEndMs,
    this.segmentOutroStartMs,
    this.locked = false,
    this.tvMode = false,
    this.canControl = true,
    this.debugLines = const <String>[],
  });

  // ── 输出与 HDR ──
  final String engine;
  final String videoOutputRequested;
  final String videoOutputActual;
  final bool nativeSurface;
  final int textureId;
  final bool hdrOutput;
  final bool displayHdr;
  final String targetTrc;
  final String? voConfigured;
  final String? currentVo;
  final String? hwdecCurrent;

  // ── Surface 诊断 ──
  final bool surfaceAttached;
  final String? surfaceId;
  final String? surfaceError;
  final int surfaceWidth;
  final int surfaceHeight;

  // ── 播放 ──
  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final bool paused;
  final bool buffering;
  final bool ended;
  final double volume;
  final double speed;

  // ── 媒体 ──
  final String? title;
  final String? mediaTitle;
  final String? videoParams;
  final String? audioParams;
  final List<NativeTrack> tracks;
  final int selectedAudioId;
  final int selectedSubtitleId;
  final double subtitleDelayMs;
  final NativeSubtitleStyle subtitleStyle;

  // ── 选集 / 版本 ──
  final List<NativeEpisode> episodes;
  final int currentEpisodeIndex;
  final List<NativeVersion> versions;
  final int currentVersionIndex;

  // ── 弹幕 ──
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuSpeed;
  final String danmakuArea;
  final List<String> danmakuBlockWords;
  final List<NativeDanmakuItem> danmakuItems;

  // ── 房间 ──
  final String? roomCode;
  final bool isHost;
  final List<NativeRoomMember> roomMembers;
  final List<NativeRoomChat> roomChat;
  final String roomSyncState;

  // ── 其他 ──
  final int? segmentIntroEndMs;
  final int? segmentOutroStartMs;
  final bool locked;
  final bool tvMode;
  final bool canControl;
  final List<String> debugLines;

  static const empty = NativePlayerState();

  factory NativePlayerState.fromJson(Map<Object?, Object?> json) {
    return NativePlayerState(
      engine: json['engine'] as String? ?? 'mpv',
      videoOutputRequested: json['videoOutputRequested'] as String? ?? 'surface',
      videoOutputActual: json['videoOutputActual'] as String? ?? 'surface',
      nativeSurface: json['nativeSurface'] == true,
      textureId: (json['textureId'] as num?)?.toInt() ?? 0,
      hdrOutput: json['hdrOutput'] == true,
      displayHdr: json['displayHdr'] == true,
      targetTrc: json['targetTrc'] as String? ?? 'auto',
      voConfigured: json['voConfigured'] as String?,
      currentVo: json['currentVo'] as String?,
      hwdecCurrent: json['hwdecCurrent'] as String?,
      surfaceAttached: json['surfaceAttached'] == true,
      surfaceId: json['surfaceId'] as String?,
      surfaceError: json['surfaceError'] as String?,
      surfaceWidth: (json['surfaceWidth'] as num?)?.toInt() ?? 0,
      surfaceHeight: (json['surfaceHeight'] as num?)?.toInt() ?? 0,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      bufferedMs: (json['bufferedMs'] as num?)?.toInt() ?? 0,
      paused: json['paused'] != false,
      buffering: json['buffering'] == true,
      ended: json['ended'] == true,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      title: json['title'] as String?,
      mediaTitle: json['mediaTitle'] as String?,
      videoParams: json['videoParams'] as String?,
      audioParams: json['audioParams'] as String?,
      tracks: ((json['tracks'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeTrack.fromJson)
          .toList(growable: false),
      selectedAudioId: (json['selectedAudioId'] as num?)?.toInt() ?? 0,
      selectedSubtitleId: (json['selectedSubtitleId'] as num?)?.toInt() ?? 0,
      subtitleDelayMs: (json['subtitleDelayMs'] as num?)?.toDouble() ?? 0.0,
      subtitleStyle: json['subtitleStyle'] is Map<Object?, Object?>
          ? NativeSubtitleStyle.fromJson(
              json['subtitleStyle']! as Map<Object?, Object?>)
          : const NativeSubtitleStyle(),
      episodes: ((json['episodes'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeEpisode.fromJson)
          .toList(growable: false),
      currentEpisodeIndex:
          (json['currentEpisodeIndex'] as num?)?.toInt() ?? 0,
      versions: ((json['versions'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeVersion.fromJson)
          .toList(growable: false),
      currentVersionIndex: (json['currentVersionIndex'] as num?)?.toInt() ?? 0,
      danmakuEnabled: json['danmakuEnabled'] == true,
      danmakuOpacity: (json['danmakuOpacity'] as num?)?.toDouble() ?? 1.0,
      danmakuFontSize: (json['danmakuFontSize'] as num?)?.toDouble() ?? 16.0,
      danmakuSpeed: (json['danmakuSpeed'] as num?)?.toDouble() ?? 1.0,
      danmakuArea: json['danmakuArea'] as String? ?? 'scroll',
      danmakuBlockWords:
          ((json['danmakuBlockWords'] as List<Object?>?) ?? const <Object?>[])
              .whereType<String>()
              .toList(growable: false),
      danmakuItems: ((json['danmakuItems'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeDanmakuItem.fromJson)
          .toList(growable: false),
      roomCode: json['roomCode'] as String?,
      isHost: json['isHost'] == true,
      roomMembers: ((json['roomMembers'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeRoomMember.fromJson)
          .toList(growable: false),
      roomChat: ((json['roomChat'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(NativeRoomChat.fromJson)
          .toList(growable: false),
      roomSyncState: json['roomSyncState'] as String? ?? 'idle',
      segmentIntroEndMs: (json['segmentIntroEndMs'] as num?)?.toInt(),
      segmentOutroStartMs: (json['segmentOutroStartMs'] as num?)?.toInt(),
      locked: json['locked'] == true,
      tvMode: json['tvMode'] == true,
      canControl: json['canControl'] != false,
      debugLines: ((json['debugLines'] as List<Object?>?) ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'engine': engine,
        'videoOutputRequested': videoOutputRequested,
        'videoOutputActual': videoOutputActual,
        'nativeSurface': nativeSurface,
        'textureId': textureId,
        'hdrOutput': hdrOutput,
        'displayHdr': displayHdr,
        'targetTrc': targetTrc,
        'voConfigured': voConfigured,
        'currentVo': currentVo,
        'hwdecCurrent': hwdecCurrent,
        'surfaceAttached': surfaceAttached,
        'surfaceId': surfaceId,
        'surfaceError': surfaceError,
        'surfaceWidth': surfaceWidth,
        'surfaceHeight': surfaceHeight,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'bufferedMs': bufferedMs,
        'paused': paused,
        'buffering': buffering,
        'ended': ended,
        'volume': volume,
        'speed': speed,
        'title': title,
        'mediaTitle': mediaTitle,
        'videoParams': videoParams,
        'audioParams': audioParams,
        'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
        'selectedAudioId': selectedAudioId,
        'selectedSubtitleId': selectedSubtitleId,
        'subtitleDelayMs': subtitleDelayMs,
        'subtitleStyle': subtitleStyle.toJson(),
        'episodes': episodes.map((e) => e.toJson()).toList(growable: false),
        'currentEpisodeIndex': currentEpisodeIndex,
        'versions': versions.map((v) => v.toJson()).toList(growable: false),
        'currentVersionIndex': currentVersionIndex,
        'danmakuEnabled': danmakuEnabled,
        'danmakuOpacity': danmakuOpacity,
        'danmakuFontSize': danmakuFontSize,
        'danmakuSpeed': danmakuSpeed,
        'danmakuArea': danmakuArea,
        'danmakuBlockWords': danmakuBlockWords,
        'danmakuItems':
            danmakuItems.map((d) => d.toJson()).toList(growable: false),
        'roomCode': roomCode,
        'isHost': isHost,
        'roomMembers':
            roomMembers.map((m) => m.toJson()).toList(growable: false),
        'roomChat': roomChat.map((c) => c.toJson()).toList(growable: false),
        'roomSyncState': roomSyncState,
        'segmentIntroEndMs': segmentIntroEndMs,
        'segmentOutroStartMs': segmentOutroStartMs,
        'locked': locked,
        'tvMode': tvMode,
        'canControl': canControl,
        'debugLines': debugLines,
      };

  NativePlayerState copyWith({
    String? engine,
    String? videoOutputRequested,
    String? videoOutputActual,
    bool? nativeSurface,
    int? textureId,
    bool? hdrOutput,
    bool? displayHdr,
    String? targetTrc,
    String? voConfigured,
    String? currentVo,
    String? hwdecCurrent,
    bool? surfaceAttached,
    String? surfaceId,
    String? surfaceError,
    int? surfaceWidth,
    int? surfaceHeight,
    int? positionMs,
    int? durationMs,
    int? bufferedMs,
    bool? paused,
    bool? buffering,
    bool? ended,
    double? volume,
    double? speed,
    String? title,
    String? mediaTitle,
    String? videoParams,
    String? audioParams,
    List<NativeTrack>? tracks,
    int? selectedAudioId,
    int? selectedSubtitleId,
    double? subtitleDelayMs,
    NativeSubtitleStyle? subtitleStyle,
    List<NativeEpisode>? episodes,
    int? currentEpisodeIndex,
    List<NativeVersion>? versions,
    int? currentVersionIndex,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontSize,
    double? danmakuSpeed,
    String? danmakuArea,
    List<String>? danmakuBlockWords,
    List<NativeDanmakuItem>? danmakuItems,
    String? roomCode,
    bool? isHost,
    List<NativeRoomMember>? roomMembers,
    List<NativeRoomChat>? roomChat,
    String? roomSyncState,
    int? segmentIntroEndMs,
    int? segmentOutroStartMs,
    bool? locked,
    bool? tvMode,
    bool? canControl,
    List<String>? debugLines,
  }) =>
      NativePlayerState(
        engine: engine ?? this.engine,
        videoOutputRequested: videoOutputRequested ?? this.videoOutputRequested,
        videoOutputActual: videoOutputActual ?? this.videoOutputActual,
        nativeSurface: nativeSurface ?? this.nativeSurface,
        textureId: textureId ?? this.textureId,
        hdrOutput: hdrOutput ?? this.hdrOutput,
        displayHdr: displayHdr ?? this.displayHdr,
        targetTrc: targetTrc ?? this.targetTrc,
        voConfigured: voConfigured ?? this.voConfigured,
        currentVo: currentVo ?? this.currentVo,
        hwdecCurrent: hwdecCurrent ?? this.hwdecCurrent,
        surfaceAttached: surfaceAttached ?? this.surfaceAttached,
        surfaceId: surfaceId ?? this.surfaceId,
        surfaceError: surfaceError ?? this.surfaceError,
        surfaceWidth: surfaceWidth ?? this.surfaceWidth,
        surfaceHeight: surfaceHeight ?? this.surfaceHeight,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        bufferedMs: bufferedMs ?? this.bufferedMs,
        paused: paused ?? this.paused,
        buffering: buffering ?? this.buffering,
        ended: ended ?? this.ended,
        volume: volume ?? this.volume,
        speed: speed ?? this.speed,
        title: title ?? this.title,
        mediaTitle: mediaTitle ?? this.mediaTitle,
        videoParams: videoParams ?? this.videoParams,
        audioParams: audioParams ?? this.audioParams,
        tracks: tracks ?? this.tracks,
        selectedAudioId: selectedAudioId ?? this.selectedAudioId,
        selectedSubtitleId: selectedSubtitleId ?? this.selectedSubtitleId,
        subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
        subtitleStyle: subtitleStyle ?? this.subtitleStyle,
        episodes: episodes ?? this.episodes,
        currentEpisodeIndex: currentEpisodeIndex ?? this.currentEpisodeIndex,
        versions: versions ?? this.versions,
        currentVersionIndex: currentVersionIndex ?? this.currentVersionIndex,
        danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
        danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
        danmakuFontSize: danmakuFontSize ?? this.danmakuFontSize,
        danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
        danmakuArea: danmakuArea ?? this.danmakuArea,
        danmakuBlockWords: danmakuBlockWords ?? this.danmakuBlockWords,
        danmakuItems: danmakuItems ?? this.danmakuItems,
        roomCode: roomCode ?? this.roomCode,
        isHost: isHost ?? this.isHost,
        roomMembers: roomMembers ?? this.roomMembers,
        roomChat: roomChat ?? this.roomChat,
        roomSyncState: roomSyncState ?? this.roomSyncState,
        segmentIntroEndMs: segmentIntroEndMs ?? this.segmentIntroEndMs,
        segmentOutroStartMs: segmentOutroStartMs ?? this.segmentOutroStartMs,
        locked: locked ?? this.locked,
        tvMode: tvMode ?? this.tvMode,
        canControl: canControl ?? this.canControl,
        debugLines: debugLines ?? this.debugLines,
      );

  /// 原生侧本地插值：播放中按 `(now - snapshotAt) * speed` 外推进度。
  ///
  /// [nowMs] 为当前时钟毫秒；[snapshotAtMs] 为快照生成时刻。
  /// 暂停/缓冲/结束时保持 positionMs 不变；外推不超过 durationMs。
  int interpolatedPositionMs(int nowMs, int snapshotAtMs) {
    if (paused || buffering || ended || speed <= 0) return positionMs;
    final delta = ((nowMs - snapshotAtMs) * speed).round();
    final projected = positionMs + delta;
    if (durationMs > 0 && projected > durationMs) return durationMs;
    return projected < 0 ? 0 : projected;
  }

  @override
  bool operator ==(Object other) =>
      other is NativePlayerState &&
      other.engine == engine &&
      other.videoOutputRequested == videoOutputRequested &&
      other.videoOutputActual == videoOutputActual &&
      other.nativeSurface == nativeSurface &&
      other.textureId == textureId &&
      other.hdrOutput == hdrOutput &&
      other.displayHdr == displayHdr &&
      other.targetTrc == targetTrc &&
      other.voConfigured == voConfigured &&
      other.currentVo == currentVo &&
      other.hwdecCurrent == hwdecCurrent &&
      other.surfaceAttached == surfaceAttached &&
      other.surfaceId == surfaceId &&
      other.surfaceError == surfaceError &&
      other.surfaceWidth == surfaceWidth &&
      other.surfaceHeight == surfaceHeight &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs &&
      other.bufferedMs == bufferedMs &&
      other.paused == paused &&
      other.buffering == buffering &&
      other.ended == ended &&
      other.volume == volume &&
      other.speed == speed &&
      other.title == title &&
      other.mediaTitle == mediaTitle &&
      other.videoParams == videoParams &&
      other.audioParams == audioParams &&
      listEquals(other.tracks, tracks) &&
      other.selectedAudioId == selectedAudioId &&
      other.selectedSubtitleId == selectedSubtitleId &&
      other.subtitleDelayMs == subtitleDelayMs &&
      other.subtitleStyle == subtitleStyle &&
      listEquals(other.episodes, episodes) &&
      other.currentEpisodeIndex == currentEpisodeIndex &&
      listEquals(other.versions, versions) &&
      other.currentVersionIndex == currentVersionIndex &&
      other.danmakuEnabled == danmakuEnabled &&
      other.danmakuOpacity == danmakuOpacity &&
      other.danmakuFontSize == danmakuFontSize &&
      other.danmakuSpeed == danmakuSpeed &&
      other.danmakuArea == danmakuArea &&
      listEquals(other.danmakuBlockWords, danmakuBlockWords) &&
      listEquals(other.danmakuItems, danmakuItems) &&
      other.roomCode == roomCode &&
      other.isHost == isHost &&
      listEquals(other.roomMembers, roomMembers) &&
      listEquals(other.roomChat, roomChat) &&
      other.roomSyncState == roomSyncState &&
      other.segmentIntroEndMs == segmentIntroEndMs &&
      other.segmentOutroStartMs == segmentOutroStartMs &&
      other.locked == locked &&
      other.tvMode == tvMode &&
      other.canControl == canControl &&
      listEquals(other.debugLines, debugLines);

  @override
  int get hashCode => Object.hashAll(<Object?>[
        engine,
        videoOutputRequested,
        videoOutputActual,
        nativeSurface,
        textureId,
        hdrOutput,
        displayHdr,
        targetTrc,
        voConfigured,
        currentVo,
        hwdecCurrent,
        surfaceAttached,
        surfaceId,
        surfaceError,
        surfaceWidth,
        surfaceHeight,
        positionMs,
        durationMs,
        bufferedMs,
        paused,
        buffering,
        ended,
        volume,
        speed,
        title,
        mediaTitle,
        videoParams,
        audioParams,
        ...tracks,
        selectedAudioId,
        selectedSubtitleId,
        subtitleDelayMs,
        subtitleStyle,
        ...episodes,
        currentEpisodeIndex,
        ...versions,
        currentVersionIndex,
        danmakuEnabled,
        danmakuOpacity,
        danmakuFontSize,
        danmakuSpeed,
        danmakuArea,
        ...danmakuBlockWords,
        ...danmakuItems,
        roomCode,
        isHost,
        ...roomMembers,
        ...roomChat,
        roomSyncState,
        segmentIntroEndMs,
        segmentOutroStartMs,
        locked,
        tvMode,
        canControl,
        ...debugLines,
      ]);
}

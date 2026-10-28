/// MPV 状态轮询结果。
class MpvPollResult {
  const MpvPollResult({
    required this.durationMs,
    required this.positionMs,
    required this.bufferedMs,
    required this.paused,
    required this.eofReached,
    required this.idleActive,
    required this.playlistCount,
    required this.pausedForCache,
    required this.cachePercent,
    this.videoParams,
    this.trackList,
    this.hwdecCurrent,
    this.gpuContext,
    this.currentVo,
    this.mediaTitle,
    this.pathMasked,
    this.surfaceAttached = false,
    this.surfaceId,
    this.surfaceError,
    this.voConfigured,
  });

  final int durationMs;
  final int positionMs;
  final int bufferedMs;
  final bool paused;
  final bool eofReached;
  final bool idleActive;
  final int playlistCount;
  final bool pausedForCache;
  final double cachePercent;
  final String? videoParams;
  final String? trackList;
  final String? hwdecCurrent;
  final String? gpuContext;
  final String? currentVo;
  final String? mediaTitle;
  final String? pathMasked;

  /// 鸿蒙 XComponent surface 是否已绑定到 mpv。
  final bool surfaceAttached;
  final String? surfaceId;
  final String? surfaceError;

  /// mpv `vo-configured`（yes/no）。
  final String? voConfigured;

  static MpvPollResult fromMap(Map<Object?, Object?> raw) {
    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    bool asBool(Object? v) => v is bool ? v : false;
    double asDouble(Object? v) =>
        v is double ? v : (v is num ? v.toDouble() : -1);
    return MpvPollResult(
      durationMs: asInt(raw['durationMs']),
      positionMs: asInt(raw['positionMs']),
      bufferedMs: asInt(raw['bufferedMs']),
      paused: asBool(raw['paused']),
      eofReached: asBool(raw['eofReached']),
      idleActive: asBool(raw['idleActive']),
      playlistCount: asInt(raw['playlistCount']),
      pausedForCache: asBool(raw['pausedForCache']),
      cachePercent: asDouble(raw['cachePercent']),
      videoParams: raw['videoParams'] as String?,
      trackList: raw['trackList'] as String?,
      hwdecCurrent: raw['hwdecCurrent'] as String?,
      gpuContext: raw['gpuContext'] as String?,
      currentVo: raw['currentVo'] as String?,
      mediaTitle: raw['mediaTitle'] as String?,
      pathMasked: raw['pathMasked'] as String?,
      surfaceAttached: asBool(raw['surfaceAttached']),
      surfaceId: raw['surfaceId'] as String?,
      surfaceError: raw['surfaceError'] as String?,
      voConfigured: raw['voConfigured'] as String?,
    );
  }
}

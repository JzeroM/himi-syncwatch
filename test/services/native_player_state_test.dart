import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_state.dart';

void main() {
  group('NativePlayerState 序列化', () {
    test('默认值', () {
      const s = NativePlayerState();
      expect(s.engine, 'mpv');
      expect(s.videoOutputRequested, 'surface');
      expect(s.videoOutputActual, 'surface');
      expect(s.nativeSurface, isTrue);
      expect(s.textureId, 0);
      expect(s.paused, isTrue);
      expect(s.volume, 1.0);
      expect(s.speed, 1.0);
      expect(s.tracks, isEmpty);
      expect(s.canControl, isTrue);
    });

    test('toJson → fromJson roundtrip 保留全部字段', () {
      const original = NativePlayerState(
        engine: 'mpv',
        videoOutputRequested: 'surface',
        videoOutputActual: 'surface',
        nativeSurface: true,
        textureId: 0,
        hdrOutput: true,
        displayHdr: true,
        targetTrc: 'pq',
        voConfigured: 'yes',
        currentVo: 'gpu-next',
        hwdecCurrent: 'videotoolbox',
        surfaceAttached: true,
        surfaceId: 'XComponent',
        surfaceError: null,
        surfaceWidth: 1920,
        surfaceHeight: 1080,
        positionMs: 12345,
        durationMs: 240000,
        bufferedMs: 30000,
        paused: false,
        buffering: false,
        ended: false,
        volume: 0.5,
        speed: 1.25,
        title: '测试标题',
        mediaTitle: 'media-title',
        videoParams: '{"w":1920}',
        audioParams: '{"channels":2}',
        tracks: <NativeTrack>[
          NativeTrack(id: 1, type: 'audio', title: 'AAC', lang: 'jpn',
              selected: true),
          NativeTrack(id: 2, type: 'sub', title: 'ASS', lang: 'chi'),
        ],
        selectedAudioId: 1,
        selectedSubtitleId: 2,
        subtitleDelayMs: -120,
        subtitleStyle: NativeSubtitleStyle(fontSize: 20, opacity: 0.8),
        episodes: <NativeEpisode>[
          NativeEpisode(index: 0, title: '第1集'),
          NativeEpisode(index: 1, title: '第2集'),
        ],
        currentEpisodeIndex: 1,
        versions: <NativeVersion>[NativeVersion(index: 0, title: '线路A')],
        currentVersionIndex: 0,
        danmakuEnabled: true,
        danmakuOpacity: 0.7,
        danmakuFontSize: 18,
        danmakuSpeed: 1.5,
        danmakuArea: 'top',
        danmakuBlockWords: <String>['广告', '剧透'],
        danmakuItems: <NativeDanmakuItem>[
          NativeDanmakuItem(timeMs: 1000, text: '前方高能', mode: 'scroll',
              color: '#FF0000'),
        ],
        roomCode: 'ROOM1',
        isHost: true,
        roomMembers: <NativeRoomMember>[
          NativeRoomMember(name: '甲', isHost: true),
          NativeRoomMember(name: '乙', online: false),
        ],
        roomChat: <NativeRoomChat>[
          NativeRoomChat(name: '甲', text: '你好', timeMs: 500),
        ],
        roomSyncState: 'synced',
        segmentIntroEndMs: 90000,
        segmentOutroStartMs: 1400000,
        locked: true,
        tvMode: false,
        canControl: true,
        debugLines: <String>['vo: gpu-next', 'hwdec: auto'],
      );

      final restored = NativePlayerState.fromJson(original.toJson());

      expect(restored.engine, original.engine);
      expect(restored.videoOutputRequested, original.videoOutputRequested);
      expect(restored.videoOutputActual, original.videoOutputActual);
      expect(restored.nativeSurface, original.nativeSurface);
      expect(restored.textureId, original.textureId);
      expect(restored.hdrOutput, original.hdrOutput);
      expect(restored.displayHdr, original.displayHdr);
      expect(restored.targetTrc, original.targetTrc);
      expect(restored.voConfigured, original.voConfigured);
      expect(restored.currentVo, original.currentVo);
      expect(restored.hwdecCurrent, original.hwdecCurrent);
      expect(restored.surfaceAttached, original.surfaceAttached);
      expect(restored.surfaceId, original.surfaceId);
      expect(restored.surfaceError, original.surfaceError);
      expect(restored.surfaceWidth, original.surfaceWidth);
      expect(restored.surfaceHeight, original.surfaceHeight);
      expect(restored.positionMs, original.positionMs);
      expect(restored.durationMs, original.durationMs);
      expect(restored.bufferedMs, original.bufferedMs);
      expect(restored.paused, original.paused);
      expect(restored.buffering, original.buffering);
      expect(restored.ended, original.ended);
      expect(restored.volume, original.volume);
      expect(restored.speed, original.speed);
      expect(restored.title, original.title);
      expect(restored.mediaTitle, original.mediaTitle);
      expect(restored.videoParams, original.videoParams);
      expect(restored.audioParams, original.audioParams);
      expect(restored.tracks, original.tracks);
      expect(restored.selectedAudioId, original.selectedAudioId);
      expect(restored.selectedSubtitleId, original.selectedSubtitleId);
      expect(restored.subtitleDelayMs, original.subtitleDelayMs);
      expect(restored.subtitleStyle, original.subtitleStyle);
      expect(restored.episodes, original.episodes);
      expect(restored.currentEpisodeIndex, original.currentEpisodeIndex);
      expect(restored.versions, original.versions);
      expect(restored.currentVersionIndex, original.currentVersionIndex);
      expect(restored.danmakuEnabled, original.danmakuEnabled);
      expect(restored.danmakuOpacity, original.danmakuOpacity);
      expect(restored.danmakuFontSize, original.danmakuFontSize);
      expect(restored.danmakuSpeed, original.danmakuSpeed);
      expect(restored.danmakuArea, original.danmakuArea);
      expect(restored.danmakuBlockWords, original.danmakuBlockWords);
      expect(restored.danmakuItems, original.danmakuItems);
      expect(restored.roomCode, original.roomCode);
      expect(restored.isHost, original.isHost);
      expect(restored.roomMembers, original.roomMembers);
      expect(restored.roomChat, original.roomChat);
      expect(restored.roomSyncState, original.roomSyncState);
      expect(restored.segmentIntroEndMs, original.segmentIntroEndMs);
      expect(restored.segmentOutroStartMs, original.segmentOutroStartMs);
      expect(restored.locked, original.locked);
      expect(restored.tvMode, original.tvMode);
      expect(restored.canControl, original.canControl);
      expect(restored.debugLines, original.debugLines);
      expect(restored, original);
    });

    test('fromJson 容忍缺失字段（旧原生包）', () {
      final s = NativePlayerState.fromJson(const <Object?, Object?>{
        'positionMs': 100,
        'paused': false,
      });
      expect(s.positionMs, 100);
      expect(s.paused, isFalse);
      expect(s.engine, 'mpv');
      expect(s.durationMs, 0);
      expect(s.tracks, isEmpty);
    });

    test('fromJson 忽略非法嵌套元素', () {
      final s = NativePlayerState.fromJson(const <Object?, Object?>{
        'tracks': <Object?>[42, null, <Object?, Object?>{'id': 3, 'type': 'audio'}],
        'debugLines': <Object?>['ok', 7],
      });
      expect(s.tracks, hasLength(1));
      expect(s.tracks.single.id, 3);
      expect(s.debugLines, ['ok']);
    });
  });

  group('NativePlayerState.interpolatedPositionMs', () {
    const base = NativePlayerState(
      positionMs: 10000,
      durationMs: 60000,
      speed: 1.0,
    );

    test('播放中按流逝时间外推', () {
      final p = base
          .copyWith(paused: false)
          .interpolatedPositionMs(10500, 10000);
      expect(p, 10500);
    });

    test('倍速外推', () {
      final p = base
          .copyWith(paused: false, speed: 2.0)
          .interpolatedPositionMs(11000, 10000);
      expect(p, 12000);
    });

    test('暂停保持不变', () {
      final p = base
          .copyWith(paused: true)
          .interpolatedPositionMs(20000, 10000);
      expect(p, 10000);
    });

    test('缓冲中保持不变', () {
      final p = base
          .copyWith(paused: false, buffering: true)
          .interpolatedPositionMs(20000, 10000);
      expect(p, 10000);
    });

    test('外推不超过时长', () {
      final p = base
          .copyWith(paused: false)
          .interpolatedPositionMs(999999, 10000);
      expect(p, 60000);
    });

    test('不为负', () {
      final p = base
          .copyWith(paused: false, speed: 0.5)
          .interpolatedPositionMs(0, 30000);
      expect(p, 0);
    });
  });

  group('NativeSubtitleStyle', () {
    test('roundtrip', () {
      const style = NativeSubtitleStyle(
          fontSize: 22, opacity: 0.6, textColor: '#FF0000');
      expect(NativeSubtitleStyle.fromJson(style.toJson()), style);
    });
  });
}

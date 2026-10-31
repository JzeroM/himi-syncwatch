import 'native_player_state.dart';

/// 原生 UI → Dart 的播放命令。
///
/// 用 sealed 层级 + `fromMap` 解析：原生侧（鸿蒙 `himi_mpv/native_ui`、
/// Android `himi_native_player`）推 JSON 命令，Dart 统一在此转换后交给
/// [NativePlayerController] 路由到 PlayerScreen / MpvPlayerAdapter。
sealed class NativePlayerCommand {
  const NativePlayerCommand();

  /// 是否需要命令执行后立即推送权威状态（跳过 200ms 防抖）。
  bool get requiresImmediatePush => false;

  Map<String, Object?> toMap();

  /// 从原生命令 map 解析；未知 type 返回 null。
  static NativePlayerCommand? fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    if (type == null) return null;
    switch (type) {
      case 'togglePlay':
        return const TogglePlay();
      case 'seekTo':
        return SeekTo(positionMs: (map['positionMs'] as num?)?.toInt() ?? 0);
      case 'seekRelative':
        return SeekRelative(
            deltaMs: (map['deltaMs'] as num?)?.toInt() ?? 0);
      case 'setVolume':
        return SetVolume(
            volume: (map['volume'] as num?)?.toDouble() ?? 1.0);
      case 'setSpeed':
        return SetSpeed(speed: (map['speed'] as num?)?.toDouble() ?? 1.0);
      case 'selectAudio':
        return SelectAudio(id: (map['id'] as num?)?.toInt() ?? 0);
      case 'selectSubtitle':
        return SelectSubtitle(id: (map['id'] as num?)?.toInt() ?? 0);
      case 'addSubtitle':
        return AddSubtitle(
          url: map['url'] as String? ?? '',
          title: map['title'] as String? ?? 'external',
          lang: map['lang'] as String? ?? 'auto',
        );
      case 'setSubtitleStyle':
        final style = map['style'];
        return SetSubtitleStyle(
          style: style is Map<Object?, Object?>
              ? NativeSubtitleStyle.fromJson(style)
              : const NativeSubtitleStyle(),
        );
      case 'setSubtitleDelay':
        return SetSubtitleDelay(
            delayMs: (map['delayMs'] as num?)?.toDouble() ?? 0.0);
      case 'selectEpisode':
        return SelectEpisode(index: (map['index'] as num?)?.toInt() ?? 0);
      case 'selectVersion':
        return SelectVersion(index: (map['index'] as num?)?.toInt() ?? 0);
      case 'switchEngine':
        return SwitchEngine(engine: map['engine'] as String? ?? 'mpv');
      case 'setDecodeMode':
        return SetDecodeMode(mode: map['mode'] as String? ?? 'auto');
      case 'adjustDisplay':
        return AdjustDisplay(
          key: map['key'] as String? ?? '',
          value: (map['value'] as num?)?.toDouble() ?? 0.0,
        );
      case 'toggleDanmaku':
        return const ToggleDanmaku();
      case 'updateDanmakuSettings':
        final values = map['values'];
        return UpdateDanmakuSettings(
          values: values is Map
              ? values.map((k, v) => MapEntry(k.toString(), v))
              : const <String, Object?>{},
        );
      case 'toggleRoomSync':
        return const ToggleRoomSync();
      case 'sendRoomChat':
        return SendRoomChat(text: map['text'] as String? ?? '');
      case 'takeScreenshot':
        return const TakeScreenshot();
      case 'toggleLock':
        return const ToggleLock();
      case 'cycleVideoFit':
        return const CycleVideoFit();
      case 'toggleOrientation':
        return const ToggleOrientation();
      case 'shareRoom':
        return const ShareRoom();
      case 'toggleResourcePanel':
        return const ToggleResourcePanel();
      case 'clearSegmentMark':
        return ClearSegmentMark(kind: map['kind'] as String? ?? 'intro');
      case 'toggleDebug':
        return const ToggleDebug();
      case 'setSegmentMark':
        return SetSegmentMark(
          kind: map['kind'] as String? ?? 'intro',
          positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
        );
      case 'requestBack':
        return const RequestBack();
      case 'requestExit':
        return const RequestExit();
      default:
        return null;
    }
  }
}

class TogglePlay extends NativePlayerCommand {
  const TogglePlay();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() => const <String, Object?>{'type': 'togglePlay'};
}

class SeekTo extends NativePlayerCommand {
  const SeekTo({required this.positionMs});

  final int positionMs;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'seekTo', 'positionMs': positionMs};
}

class SeekRelative extends NativePlayerCommand {
  const SeekRelative({required this.deltaMs});

  final int deltaMs;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'seekRelative', 'deltaMs': deltaMs};
}

class SetVolume extends NativePlayerCommand {
  const SetVolume({required this.volume});

  final double volume;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'setVolume', 'volume': volume};
}

class SetSpeed extends NativePlayerCommand {
  const SetSpeed({required this.speed});

  final double speed;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'setSpeed', 'speed': speed};
}

class SelectAudio extends NativePlayerCommand {
  const SelectAudio({required this.id});

  final int id;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'selectAudio', 'id': id};
}

class SelectSubtitle extends NativePlayerCommand {
  const SelectSubtitle({required this.id});

  final int id;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'selectSubtitle', 'id': id};
}

class AddSubtitle extends NativePlayerCommand {
  const AddSubtitle({
    required this.url,
    this.title = 'external',
    this.lang = 'auto',
  });

  final String url;
  final String title;
  final String lang;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'type': 'addSubtitle',
        'url': url,
        'title': title,
        'lang': lang,
      };
}

class SetSubtitleStyle extends NativePlayerCommand {
  const SetSubtitleStyle({required this.style});

  final NativeSubtitleStyle style;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'setSubtitleStyle', 'style': style.toJson()};
}

class SetSubtitleDelay extends NativePlayerCommand {
  const SetSubtitleDelay({required this.delayMs});

  final double delayMs;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'setSubtitleDelay', 'delayMs': delayMs};
}

class SelectEpisode extends NativePlayerCommand {
  const SelectEpisode({required this.index});

  final int index;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'selectEpisode', 'index': index};
}

class SelectVersion extends NativePlayerCommand {
  const SelectVersion({required this.index});

  final int index;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'selectVersion', 'index': index};
}

class SwitchEngine extends NativePlayerCommand {
  const SwitchEngine({required this.engine});

  final String engine;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'switchEngine', 'engine': engine};
}

class SetDecodeMode extends NativePlayerCommand {
  const SetDecodeMode({required this.mode});

  final String mode;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'setDecodeMode', 'mode': mode};
}

class AdjustDisplay extends NativePlayerCommand {
  const AdjustDisplay({required this.key, required this.value});

  final String key;
  final double value;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'adjustDisplay', 'key': key, 'value': value};
}

class ToggleDanmaku extends NativePlayerCommand {
  const ToggleDanmaku();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'toggleDanmaku'};
}

class UpdateDanmakuSettings extends NativePlayerCommand {
  const UpdateDanmakuSettings({required this.values});

  final Map<String, Object?> values;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'updateDanmakuSettings', 'values': values};
}

class ToggleRoomSync extends NativePlayerCommand {
  const ToggleRoomSync();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'toggleRoomSync'};
}

class SendRoomChat extends NativePlayerCommand {
  const SendRoomChat({required this.text});

  final String text;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'sendRoomChat', 'text': text};
}

class TakeScreenshot extends NativePlayerCommand {
  const TakeScreenshot();

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'takeScreenshot'};
}

/// 锁定/解锁屏幕（手机左锁钮）。
class ToggleLock extends NativePlayerCommand {
  const ToggleLock();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'toggleLock'};
}

/// 画面比例循环切换（自适应→裁剪→铺满→原始）。
class CycleVideoFit extends NativePlayerCommand {
  const CycleVideoFit();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'cycleVideoFit'};
}

/// 手机手动转屏（命令回 Flutter 的 `_toggleOrientation`）。
class ToggleOrientation extends NativePlayerCommand {
  const ToggleOrientation();

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'toggleOrientation'};
}

/// 房间分享（顶栏分享按钮；对齐 Flutter showShare/onShare）。
class ShareRoom extends NativePlayerCommand {
  const ShareRoom();

  @override
  Map<String, Object?> toMap() => const <String, Object?>{'type': 'shareRoom'};
}

/// 房间模式「资源面板」开关（对齐 Flutter `_showPanel`）。
///
/// Flutter 底栏在房间模式下有个 `open_in_full`/`close_fullscreen` 按钮，
/// 点它切换视频区与资源面板的分栏。原生 UI 的资源面板属 Phase 5（尚未
/// 实现），但按钮**必须存在且语义正确**——旧实现点它发 `requestBack`，
/// 直接把用户退出播放页。
class ToggleResourcePanel extends NativePlayerCommand {
  const ToggleResourcePanel();

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'toggleResourcePanel'};
}

/// 清除片头/片尾标记（原生二次确认里的「清除」）。
class ClearSegmentMark extends NativePlayerCommand {
  const ClearSegmentMark({required this.kind});

  /// intro / outro。
  final String kind;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      <String, Object?>{'type': 'clearSegmentMark', 'kind': kind};
}

class ToggleDebug extends NativePlayerCommand {
  const ToggleDebug();

  @override
  Map<String, Object?> toMap() => const <String, Object?>{'type': 'toggleDebug'};
}

class SetSegmentMark extends NativePlayerCommand {
  const SetSegmentMark({required this.kind, required this.positionMs});

  /// intro / outro。
  final String kind;
  final int positionMs;

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'type': 'setSegmentMark',
        'kind': kind,
        'positionMs': positionMs,
      };
}

class RequestBack extends NativePlayerCommand {
  const RequestBack();

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'requestBack'};
}

class RequestExit extends NativePlayerCommand {
  const RequestExit();

  @override
  bool get requiresImmediatePush => true;

  @override
  Map<String, Object?> toMap() =>
      const <String, Object?>{'type': 'requestExit'};
}

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_command.dart';
import 'package:himi_syncwatch/services/player/native/native_player_state.dart';

void main() {
  group('NativePlayerCommand.fromMap', () {
    test('未知 type 返回 null', () {
      expect(NativePlayerCommand.fromMap(const {'type': 'nope'}), isNull);
      expect(NativePlayerCommand.fromMap(const {'x': 1}), isNull);
    });

    test('togglePlay / seekTo / seekRelative', () {
      final toggle =
          NativePlayerCommand.fromMap(const {'type': 'togglePlay'});
      expect(toggle, isA<TogglePlay>());
      expect(toggle!.requiresImmediatePush, isTrue);

      final seek = NativePlayerCommand.fromMap(
          const {'type': 'seekTo', 'positionMs': 90000});
      expect(seek, isA<SeekTo>());
      expect((seek as SeekTo).positionMs, 90000);
      expect(seek.requiresImmediatePush, isTrue);

      final rel = NativePlayerCommand.fromMap(
          const {'type': 'seekRelative', 'deltaMs': -10000});
      expect(rel, isA<SeekRelative>());
      expect((rel as SeekRelative).deltaMs, -10000);
    });

    test('setVolume / setSpeed', () {
      final vol = NativePlayerCommand.fromMap(
          const {'type': 'setVolume', 'volume': 0.3});
      expect(vol, isA<SetVolume>());
      expect((vol as SetVolume).volume, closeTo(0.3, 1e-9));
      expect(vol.requiresImmediatePush, isFalse);

      final speed = NativePlayerCommand.fromMap(
          const {'type': 'setSpeed', 'speed': 1.5});
      expect(speed, isA<SetSpeed>());
      expect((speed as SetSpeed).speed, closeTo(1.5, 1e-9));
    });

    test('轨道选择', () {
      final audio = NativePlayerCommand.fromMap(
          const {'type': 'selectAudio', 'id': 2});
      expect(audio, isA<SelectAudio>());
      expect((audio as SelectAudio).id, 2);

      final sub = NativePlayerCommand.fromMap(
          const {'type': 'selectSubtitle', 'id': 0});
      expect(sub, isA<SelectSubtitle>());
      expect((sub as SelectSubtitle).id, 0);
    });

    test('外挂字幕与样式', () {
      final add = NativePlayerCommand.fromMap(const {
        'type': 'addSubtitle',
        'url': 'https://x/sub.ass',
        'title': '外挂',
        'lang': 'chi',
      });
      expect(add, isA<AddSubtitle>());
      expect((add as AddSubtitle).url, 'https://x/sub.ass');
      expect(add.title, '外挂');
      expect(add.lang, 'chi');

      final style = NativePlayerCommand.fromMap(const {
        'type': 'setSubtitleStyle',
        'style': <Object?, Object?>{'fontSize': 20, 'opacity': 0.5},
      });
      expect(style, isA<SetSubtitleStyle>());
      expect((style as SetSubtitleStyle).style.fontSize, 20);
      expect(style.style.opacity, closeTo(0.5, 1e-9));

      final delay = NativePlayerCommand.fromMap(
          const {'type': 'setSubtitleDelay', 'delayMs': -240});
      expect(delay, isA<SetSubtitleDelay>());
      expect((delay as SetSubtitleDelay).delayMs, closeTo(-240, 1e-9));
    });

    test('选集 / 版本 / 内核 / 解码 / 显示', () {
      expect(
        NativePlayerCommand.fromMap(const {'type': 'selectEpisode', 'index': 3}),
        isA<SelectEpisode>(),
      );
      expect(
        NativePlayerCommand.fromMap(const {'type': 'selectVersion', 'index': 1}),
        isA<SelectVersion>(),
      );
      final engine = NativePlayerCommand.fromMap(
          const {'type': 'switchEngine', 'engine': 'mdk'});
      expect(engine, isA<SwitchEngine>());
      expect((engine as SwitchEngine).engine, 'mdk');

      final decode = NativePlayerCommand.fromMap(
          const {'type': 'setDecodeMode', 'mode': 'software'});
      expect(decode, isA<SetDecodeMode>());
      expect((decode as SetDecodeMode).mode, 'software');

      final display = NativePlayerCommand.fromMap(const {
        'type': 'adjustDisplay',
        'key': 'brightness',
        'value': 0.2,
      });
      expect(display, isA<AdjustDisplay>());
      expect((display as AdjustDisplay).key, 'brightness');
      expect(display.value, closeTo(0.2, 1e-9));
    });

    test('弹幕命令', () {
      expect(
        NativePlayerCommand.fromMap(const {'type': 'toggleDanmaku'}),
        isA<ToggleDanmaku>(),
      );
      final settings = NativePlayerCommand.fromMap(const {
        'type': 'updateDanmakuSettings',
        'values': <Object?, Object?>{'opacity': 0.8, 'area': 'bottom'},
      });
      expect(settings, isA<UpdateDanmakuSettings>());
      expect((settings as UpdateDanmakuSettings).values['opacity'], 0.8);
      expect(settings.values['area'], 'bottom');
    });

    test('房间 / 截图 / 调试 / 片头片尾 / 返回退出', () {
      expect(
        NativePlayerCommand.fromMap(const {'type': 'toggleRoomSync'}),
        isA<ToggleRoomSync>(),
      );
      final chat = NativePlayerCommand.fromMap(
          const {'type': 'sendRoomChat', 'text': '你好'});
      expect(chat, isA<SendRoomChat>());
      expect((chat as SendRoomChat).text, '你好');

      expect(
        NativePlayerCommand.fromMap(const {'type': 'takeScreenshot'}),
        isA<TakeScreenshot>(),
      );
      expect(
        NativePlayerCommand.fromMap(const {'type': 'toggleDebug'}),
        isA<ToggleDebug>(),
      );

      final seg = NativePlayerCommand.fromMap(const {
        'type': 'setSegmentMark',
        'kind': 'outro',
        'positionMs': 1400000,
      });
      expect(seg, isA<SetSegmentMark>());
      expect((seg as SetSegmentMark).kind, 'outro');
      expect(seg.positionMs, 1400000);

      expect(
        NativePlayerCommand.fromMap(const {'type': 'requestBack'}),
        isA<RequestBack>(),
      );
      final exit =
          NativePlayerCommand.fromMap(const {'type': 'requestExit'});
      expect(exit, isA<RequestExit>());
      expect(exit!.requiresImmediatePush, isTrue);
    });

    test('Phase 2.5 新命令：锁定/比例/转屏/清除片头片尾', () {
      final lock = NativePlayerCommand.fromMap(const {'type': 'toggleLock'});
      expect(lock, isA<ToggleLock>());
      expect(lock!.requiresImmediatePush, isTrue);

      final fit = NativePlayerCommand.fromMap(const {'type': 'cycleVideoFit'});
      expect(fit, isA<CycleVideoFit>());
      expect(fit!.requiresImmediatePush, isTrue);

      final orientation =
          NativePlayerCommand.fromMap(const {'type': 'toggleOrientation'});
      expect(orientation, isA<ToggleOrientation>());

      final clear = NativePlayerCommand.fromMap(const {
        'type': 'clearSegmentMark',
        'kind': 'outro',
      });
      expect(clear, isA<ClearSegmentMark>());
      expect((clear as ClearSegmentMark).kind, 'outro');
      expect(clear.requiresImmediatePush, isTrue);

      // kind 缺省回落 intro，不崩。
      final clearDefault = NativePlayerCommand.fromMap(
          const {'type': 'clearSegmentMark'});
      expect((clearDefault as ClearSegmentMark).kind, 'intro');
    });

    test('toMap → fromMap roundtrip', () {
      const commands = <NativePlayerCommand>[
        TogglePlay(),
        SeekTo(positionMs: 1234),
        SeekRelative(deltaMs: -10000),
        SetVolume(volume: 0.42),
        SetSpeed(speed: 2.0),
        SelectAudio(id: 1),
        SelectSubtitle(id: 2),
        AddSubtitle(url: 'u', title: 't', lang: 'l'),
        SetSubtitleStyle(style: NativeSubtitleStyle(fontSize: 19)),
        SetSubtitleDelay(delayMs: 300),
        SelectEpisode(index: 4),
        SelectVersion(index: 0),
        SwitchEngine(engine: 'mpv'),
        SetDecodeMode(mode: 'auto'),
        AdjustDisplay(key: 'gamma', value: 0.1),
        ToggleDanmaku(),
        UpdateDanmakuSettings(values: <String, Object?>{'speed': 1.2}),
        ToggleRoomSync(),
        SendRoomChat(text: 'hi'),
        TakeScreenshot(),
        ToggleDebug(),
        SetSegmentMark(kind: 'intro', positionMs: 90000),
        ClearSegmentMark(kind: 'outro'),
        ToggleLock(),
        CycleVideoFit(),
        ToggleOrientation(),
        RequestBack(),
        RequestExit(),
      ];
      for (final command in commands) {
        final parsed = NativePlayerCommand.fromMap(command.toMap());
        expect(parsed.runtimeType, command.runtimeType,
            reason: 'roundtrip 失败: ${command.toMap()}');
        expect(parsed!.toMap(), command.toMap());
      }
    });
  });

  group('立即推送标记', () {
    test('内容变化类命令要求立即推送', () {
      expect(const TogglePlay().requiresImmediatePush, isTrue);
      expect(const SeekTo(positionMs: 0).requiresImmediatePush, isTrue);
      expect(const SelectEpisode(index: 0).requiresImmediatePush, isTrue);
      expect(const SetSpeed(speed: 1).requiresImmediatePush, isTrue);
    });

    test('高频命令不强制立即推送', () {
      expect(const SetVolume(volume: 0.5).requiresImmediatePush, isFalse);
      expect(const TakeScreenshot().requiresImmediatePush, isFalse);
      expect(const RequestBack().requiresImmediatePush, isFalse);
    });
  });
}

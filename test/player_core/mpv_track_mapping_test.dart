import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 617：MPV 音轨/字幕按 **Emby 服务端流顺序** 映射（修复「选的和实际不一致」）。
///
/// 三处缺陷叠加：
/// 1. `_parseTracks` 只认 List（安卓返回分组 Map）→ 整段跳过；
/// 2. `id is! int`（media_kit 的 id 是 String）→ 全部跳过；
/// 3. 映射表恒空 → 选轨退回「Emby 索引 + 1」，而 media_kit 的 tracks 前置
///    `[auto, no]` 两条伪轨 → 选第 1 条落到 `auto`、第 2 条落到 `no`。
void main() {
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final windows = File(
    'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart',
  ).readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();

  /// 提取函数体（从 `signature` 起到配平的大括号）。
  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① _parseTracks 兼容两种 track-list 结构', () {
    test('同时支持 List（鸿蒙 mpv 原生）与 Map（安卓分组）', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      // 旧实现 `if (decoded is! List) return;` 必须消失。
      expect(body, isNot(contains('if (decoded is! List) return;')));
      expect(body, contains('decoded is List'));
      expect(body, contains('decoded is Map'));
    });

    test('Map 分支按 audio/subtitle 分组取轨', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains("decoded['audio']"));
      expect(body, contains("decoded['subtitle']"));
    });

    test('List 分支按 type 字段取轨', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains("track['type']"));
    });
  });

  group('② track id 类型兼容（media_kit 是 String）', () {
    test('不再要求 id 必须是 int', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      // 旧实现 `if (id is! int) continue;` 必须消失。
      expect(body, isNot(contains('if (id is! int) continue;')));
      expect(body, contains('raw is int'));
      expect(body, contains('raw is String'));
      expect(body, contains('int.tryParse(raw)'));
    });
  });

  group('③ 顺序保持 Emby 服务端流顺序', () {
    test('音轨/字幕 id 表按出现顺序追加', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains('audioIds.add(id)'));
      expect(body, contains('subIds.add(id)'));
      // 不排序、不反转——顺序即 Emby 流顺序。
      expect(body, isNot(contains('audioIds.sort')));
      expect(body, isNot(contains('subIds.sort')));
      expect(body, isNot(contains('reversed')));
    });

    test('两类都落表（空也要清空，防上一集残留）', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      // 旧实现 `if (audioIds.isNotEmpty)` 才覆盖 → 换集后旧 id 残留。
      expect(body, isNot(contains('if (audioIds.isNotEmpty)')));
      expect(body, isNot(contains('if (subIds.isNotEmpty)')));
      expect(body, contains('_audioTrackIds'));
      expect(body, contains('_subtitleTrackIds'));
    });

    test('字幕轨数用解析结果而非旧值', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains('subtitleCount: subIds.length'));
    });
  });

  group('④ 解析失败不再静默（本 bug 潜伏的根因）', () {
    test('有轨道但解析不出 id 时打日志（619：空表不再误报）', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains('track-list 有轨道但解析无 id'));
      expect(body, contains("LogService().log('mpv'"));
      // 619：起播早期空表是正常状态，不得报警（真机日志曾被刷 20+ 条）。
      expect(body, contains('hasRawTracks'));
    });

    test('异常不再被空 catch 吞掉', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, isNot(contains('} catch (_) {}')));
      expect(body, contains('track-list 解析失败'));
    });
  });

  group('⑤ 安卓/Windows 剔除 media_kit 的 auto/no 伪轨', () {
    for (final (name, src) in [('安卓', android), ('Windows', windows)]) {
      test('$name：_isRealTrack 排除 auto/no', () {
        expect(src, contains('static bool _isRealTrack(dynamic track)'));
        expect(src, contains("id != 'auto' && id != 'no'"));
      });

      test('$name：getTracks 过滤伪轨（消除 +2 偏移）', () {
        final body = bodyOf(src, 'Future<String?> getTracks() async {');
        expect(body, contains('tracks.audio.where(_isRealTrack)'));
        expect(body, contains('tracks.subtitle.where(_isRealTrack)'));
        // 旧写法（不过滤）必须消失。
        expect(body, isNot(contains('tracks.audio.map(_trackJson)')));
        expect(body, isNot(contains('tracks.subtitle.map(_trackJson)')));
      });

      test('$name：选轨按真实 track id 优先', () {
        final audio = bodyOf(src, 'Future<void> setAudioTrack(int id) async {');
        expect(audio, contains('_realAudioTracks()'));
        expect(audio, contains('int.tryParse(t.id) == id'));
        // 618 改为三元表达式（byTrackId ?? 序号兜底）。
        expect(audio, contains('byTrackId ??'));
        expect(audio, contains('synchronized: false'));

        final sub =
            bodyOf(src, 'Future<void> setSubtitleTrack(int id) async {');
        expect(sub, contains('_realSubtitleTracks()'));
        expect(sub, contains('int.tryParse(t.id) == id'));
        expect(sub, contains('synchronized: false'));
      });

      test('$name：id<=0 走 no()（关闭语义）', () {
        final audio = bodyOf(src, 'Future<void> setAudioTrack(int id) async {');
        expect(audio, contains('AudioTrack.no()'));
        final sub =
            bodyOf(src, 'Future<void> setSubtitleTrack(int id) async {');
        expect(sub, contains('SubtitleTrack.no()'));
      });
    }
  });

  group('⑥ 外挂字幕单独处理（sub-add 追加到末尾）', () {
    test('不再按 Emby 索引选外挂轨', () {
      final idx = screen.indexOf('Future<void> _selectEmbySubtitle(int embyIndex)');
      expect(idx, greaterThan(0));
      final end = screen.indexOf('_useServerSubtitleBurnIn = false;', idx);
      final body = screen.substring(idx, end);
      // 外挂分支（isExternal 到 else）里不能出现按 Emby 索引选轨。
      final externalIdx = body.indexOf('if (isExternal) {');
      expect(externalIdx, greaterThan(0));
      final elseIdx = body.indexOf('// 内嵌字幕', externalIdx);
      expect(elseIdx, greaterThan(externalIdx));
      final externalBody = body.substring(externalIdx, elseIdx);
      expect(
        externalBody,
        isNot(contains('_player.activeSubtitleTracks = [embyIndex];')),
      );
      // 改为「真实轨数 - 1」选中末尾那条。
      expect(externalBody, contains('count - 1'));
    });

    test('内嵌字幕仍按 Emby 顺序映射', () {
      final idx = screen.indexOf('Future<void> _selectEmbySubtitle(int embyIndex)');
      final end = screen.indexOf('_useServerSubtitleBurnIn = false;', idx);
      final body = screen.substring(idx, end);
      expect(body, contains('_player.activeSubtitleTracks = [embyIndex];'));
    });
  });

  group('⑦ Dart 侧空列表语义（关闭音频）', () {
    test('activeAudioTracks 空列表下发 0（关闭）', () {
      final setter = bodyOf(adapter, 'set activeAudioTracks(List<int> tracks) {');
      expect(setter, contains('setAudioTrack(0)'));
    });

    test('activeSubtitleTracks 空列表下发 0（关闭）', () {
      final setter = bodyOf(
        adapter,
        'set activeSubtitleTracks(List<int> tracks) {',
      );
      expect(setter, contains('setSubtitleTrack(0)'));
    });
  });

  group('⑧ 鸿蒙 aid/sid 收真实 mpv track id', () {
    test('setAudioTrack 写 aid、setSubtitleTrack 写 sid', () {
      final ohos = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      ).readAsStringSync();
      expect(ohos, contains("setProperty('aid', this.number(args, 'id', 0))"));
      expect(ohos, contains("setProperty('sid', this.number(args, 'id', 0))"));
      // 注释记录 617 的语义约定（id = 真实 mpv track id）。
      expect(ohos, contains('真实 mpv track id'));
    });

    test('鸿蒙 getTracks 返回 mpv 原生 track-list（Dart 侧 List 分支可解析）', () {
      final ohos = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      ).readAsStringSync();
      expect(ohos, contains("getPropertyByName('track-list')"));
    });
  });
}

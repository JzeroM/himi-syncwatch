import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 620：MPV 字幕延迟改用原生 `sub-delay`（替代重写字幕文件）。
///
/// 旧实现（重写文件）的四个痛点：
/// ① 要等几秒（下载 → 改写 → 写盘 → sub-add）；
/// ② 位图字幕（PGS/VobSub）**无法改写**（二进制）→ 延迟彻底失效；
/// ③ 连续拖动**堆积多条临时轨**（每次 sub-add 都新增一条）；
/// ④ 归零要重新下载原轨（黑屏一瞬）+ 每次都有网络往返。
///
/// `sub-delay` 是**单个 mpv 属性**：立即生效、毫秒精度、对位图字幕
/// 同样有效、零网络、不动字幕内容（不影响 ASS 的 \move/\fade 相对时序）。
void main() {
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final panel = File(
    'lib/screens/player/widgets/subtitle_style_panel.dart',
  ).readAsStringSync();
  final mpvAdapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final shifter = File('lib/services/subtitle_shifter.dart').readAsStringSync();

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
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

  group('① 面板语义：正 = 晚显示（与 mpv sub-delay 同向）', () {
    test('面板注释明确「正=晚显示」', () {
      expect(panel, contains('正=晚显示'));
    });

    test('范围 ±5000ms、步进 100ms', () {
      expect(panel, contains('minDelayMs = -5000'));
      expect(panel, contains('maxDelayMs = 5000'));
      expect(panel, contains('delayStepMs = 100'));
    });

    test('旧重写方案的符号方向也是「时间轴后移 = 晚显示」', () {
      // _shiftSrtToken: base + deltaMs（时间轴后移）。
      expect(shifter, contains('base + deltaMs'));
    });
  });

  group('② MPV 走原生 sub-delay（不再重写文件）', () {
    test('_applyMpvSubtitleDelay 存在且写 sub-delay', () {
      final body = bodyOf(screen, 'void _applyMpvSubtitleDelay(int delayMs) {');
      expect(body, contains("setProperty('sub-delay'"));
      // 毫秒 → 秒（mpv 单位是秒）。
      expect(body, contains('delayMs / 1000.0'));
      expect(body, contains('toStringAsFixed(3)'));
    });

    test('滑杆变更时 MPV 分流到 sub-delay 并 early-return', () {
      final body = bodyOf(screen, 'void _onSubtitleDelayChanged(int v) {');
      expect(body, contains('if (_currentEngine == PlayerEngine.mpv)'));
      expect(body, contains('_applyMpvSubtitleDelay(v)'));
      expect(body, contains('return;'));
      // 其他引擎保留重写文件方案。
      expect(body, contains('_maybeApplySubtitleDelay()'));
    });

    test('MPV 路径不再触发 _reloadSubtitleForDelay（零下载/零写盘）', () {
      final body = bodyOf(screen, 'void _onSubtitleDelayChanged(int v) {');
      // MPV 分支必须在「重写文件」逻辑之前 return。
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final reloadIdx = body.indexOf('_maybeApplySubtitleDelay()');
      expect(mpvIdx, greaterThan(0));
      expect(reloadIdx, greaterThan(mpvIdx));
    });
  });

  group('③ 切轨后 sub-delay 随样式一起落（不重建字幕链两次）', () {
    test('_applySubtitleStyle 的 MPV 分支含 sub-delay', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      expect(mpvIdx, greaterThan(0));
      final mpvBody = body.substring(mpvIdx);
      expect(mpvBody, contains("'sub-scale'"));
      expect(mpvBody, contains("'sub-pos'"));
      expect(mpvBody, contains("'sub-delay'"));
      expect(mpvBody, contains('_subtitleDelayMs / 1000.0'));
    });

    test('切轨窗口补写只调 _applySubtitleStyle（已含 delay，不重复写）', () {
      final body = bodyOf(screen, 'void _enterTrackSwitchWindow() {');
      expect(body, contains('_applySubtitleStyle()'));
      // 不应再单独调 _applyMpvSubtitleDelay（会重复写属性）。
      expect(body, isNot(contains('_applyMpvSubtitleDelay')));
    });
  });

  group('④ 归零：MPV 只写 0，不重新下载原轨', () {
    test('_onSubtitleStyleReset 的 MPV 分支写 sub-delay=0', () {
      final body = bodyOf(screen, 'void _onSubtitleStyleReset() {');
      expect(body, contains('_applyMpvSubtitleDelay(0)'));
      // 非 MPV 才恢复原素材轨。
      expect(body, contains('_restoreActiveSubtitleSource()'));
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final restoreIdx = body.indexOf('_restoreActiveSubtitleSource()');
      expect(mpvIdx, greaterThan(0));
      expect(restoreIdx, greaterThan(mpvIdx));
    });
  });

  group('⑤ 切字幕时 MPV 不再走偏移重载', () {
    test('_selectEmbySubtitle 的 _maybeApplySubtitleDelay 仅在非 MPV 执行', () {
      final body =
          bodyOf(screen, 'Future<void> _selectEmbySubtitle(int embyIndex) async {');
      expect(body, contains('if (_currentEngine != PlayerEngine.mpv)'));
      expect(body, contains('_maybeApplySubtitleDelay()'));
    });
  });

  group('⑥ setProperty 通道已就绪（无需新链路）', () {
    test('MPV 适配器 setProperty 转发到原生', () {
      // PlayerAdapter 接口声明 setProperty；mpv adapter 继承实现。
      final adapter = File('lib/services/player/player_adapter.dart')
          .readAsStringSync();
      expect(adapter, contains('void setProperty(String name, String value)'));
    });

    test('已有 sub-scale / sub-pos 走同一通道（sub-delay 可复用）', () {
      expect(mpvAdapter, contains("setProperty('hwdec'"));
      // 证明 setProperty 是通用属性通道。
      expect(mpvAdapter, contains('setProperty'));
    });
  });

  group('⑦ 保留：其他引擎无等价属性 → 仍走重写文件', () {
    test('_reloadSubtitleForDelay 仍存在（供 MDK/media_kit/Erika 使用）', () {
      expect(screen, contains('Future<void> _reloadSubtitleForDelay()'));
      expect(screen, contains('SubtitleDelayFile.write'));
    });

    test('_restoreActiveSubtitleSource 仍存在', () {
      expect(screen, contains('void _restoreActiveSubtitleSource()'));
    });
  });
}

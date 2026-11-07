import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 621：MPV 字幕**位置**属性按字幕类型分流（mpv 官方手册分工）。
///
/// | 类型 | 位置属性 | 手册依据 |
/// |---|---|---|
/// | SRT/VTT（无样式文本） | `sub-margin-y`（像素） | *Using `--sub-margin-y`
///   can achieve this in a better way* |
/// | ASS/SSA（自带样式） | `sub-pos`（%） | *This affects ASS subtitles as
///   well*；`sub-margin-y` 只对 **unstyled** text 生效 |
/// | PGS/VobSub/DVB（位图） | **都无效** | *cannot be changed for fundamental
///   reasons* |
///
/// 旧实现统一 `sub-pos` + `(100 - marginY/4)`：
/// - 0~200px 被 **4 倍压缩**成 0~50 的百分比变化 → 每 4px 才动 1 格（跳格）；
/// - `clamp(0, 150)` 允许到 150，但手册警告 **>100 文本字幕会被裁切**。
///
/// 另：`sub-delay` 只改**时间轴**（何时出现），**不能**改位置——三者互不替代。
void main() {
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final panel = File(
    'lib/screens/player/widgets/display_adjust_panel.dart',
  ).readAsStringSync();

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

  group('① 位置统一走 sub-pos（不按字幕类型分流）', () {
    test('不再按 ASS 分流（_activeSubtitleIsAss 已移除）', () {
      expect(screen, isNot(contains('_activeSubtitleIsAss')));
    });

    test('_activeSubtitleIsBitmap 仍存在（供 MDK 位图对齐用）', () {
      expect(screen, contains('bool get _activeSubtitleIsBitmap'));
      expect(screen, contains('PlayerScreen.isBitmapSubtitleCodec'));
    });
  });

  group('② 位置统一 sub-pos', () {
    test('MPV 写 sub-pos（不再用 sub-margin-y）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      expect(mpvIdx, greaterThan(0));
      final mpvBody = body.substring(mpvIdx);
      expect(mpvBody, contains("setProperty('sub-pos'"));
      // 分流策略已取消：不再写 sub-margin-y。
      final code = mpvBody
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains("'sub-margin-y'")));
    });

    test('MPV 分支内不依赖字幕类型（MDK 分支仍可引用）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      // MPV 分支在 `return;` 处结束——只截取到那里（之后是 MDK 分支，
      // 它合法地引用 _activeSubtitleIsBitmap 做位图底部对齐）。
      final mpvEnd = body.indexOf('      return;', mpvIdx);
      expect(mpvEnd, greaterThan(mpvIdx));
      final mpvBody = body.substring(mpvIdx, mpvEnd);
      final code = mpvBody
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('_activeSubtitleIsAss')));
      expect(code, isNot(contains('_activeSubtitleIsBitmap')));
    });

    test('sub-pos 限制 0~100（手册警告 >100 会被裁切）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final mpvBody = body.substring(mpvIdx);
      expect(mpvBody, contains('clamp(0, 100)'));
      // 注释里保留了「旧实现 clamp(0,150)」的说明，故只查代码行。
      final code = mpvBody
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('clamp(0, 150)')));
    });

    test('注释记录 clamp 0~100 的手册依据（>100 会被裁切）', () {
      expect(screen, contains('cut off'));
      expect(screen, contains('This affects ASS'));
    });
  });

  group('③ sub-delay 只改时间轴，不替代位置', () {
    test('延迟仍独立写 sub-delay（秒）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final mpvBody = body.substring(mpvIdx);
      // 多行调用：setProperty(\n  'sub-delay',\n  ...
      expect(mpvBody, contains("'sub-delay'"));
      expect(mpvBody, contains('_subtitleDelayMs / 1000.0'));
    });

    test('位置与延迟是两条独立写入（互不替代）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final mpvBody = body.substring(mpvIdx);
      final posIdx = mpvBody.indexOf("'sub-pos'");
      final delayIdx = mpvBody.indexOf("'sub-delay'");
      expect(posIdx, greaterThan(0));
      expect(delayIdx, greaterThan(posIdx));
    });
  });

  group('④ 位图字幕面板：保持可调（只限 Erika 禁用）', () {
    test('_erikaActiveSubtitleIsBitmap 仍限定 Erika', () {
      // 621 曾尝试扩展到 MPV，但会把「延迟」也一起禁掉——
      // 而 sub-delay 对位图字幕是**有效**的（手册只限制样式/位置）。
      // 故回退：只有 Erika 禁用整段面板。
      expect(
        screen,
        contains('bool _erikaActiveSubtitleIsBitmap() =>'),
      );
      expect(
        screen,
        contains('_currentEngine == PlayerEngine.erika && _activeSubtitleIsBitmap'),
      );
    });

    test('面板提示文案存在（Erika 位图时使用）', () {
      expect(panel, contains('位图字幕（PGS 等）不支持样式调节'));
      expect(panel, contains('subtitleStyleDisabled'));
    });

    test('调用点保持方法调用形式', () {
      expect(
        screen,
        contains('subtitleStyleDisabled: _erikaActiveSubtitleIsBitmap(),'),
      );
    });

    test('MPV + 位图仍可写 sub-pos / sub-scale / sub-delay（不被禁用）', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      final mpvIdx = body.indexOf('PlayerEngine.mpv');
      final mpvBody = body.substring(mpvIdx);
      // 三项都要写：位图时 sub-pos 分支仍执行，delay 无条件写。
      expect(mpvBody, contains("'sub-pos'"));
      expect(mpvBody, contains("'sub-scale'"));
      expect(mpvBody, contains("'sub-delay'"));
    });
  });

  group('⑥ 弹幕 update() 无效重绘优化（621）', () {
    final danmaku = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'DanmakuLayerView.kt',
    ).readAsStringSync();

    test('存在内容签名字段', () {
      expect(danmaku, contains('private var lastContentSignature = -1'));
    });

    test('update() 仅在可见性/内容真变时 invalidate', () {
      final body = bodyOf(danmaku, 'fun update(');
      expect(body, contains('val visibilityChanged = visibility != newVisibility'));
      expect(body, contains('val contentChanged = newSignature != lastContentSignature'));
      expect(body, contains('if (visibilityChanged || contentChanged) invalidate()'));
      // 旧的「无条件 invalidate」必须消失。
      expect(body, isNot(contains('visibility = if (enabled && items.isNotEmpty()) VISIBLE else GONE\n        invalidate()')));
    });

    test('签名覆盖「窗口滑动」场景（条数 + 首尾时间）', () {
      final body = bodyOf(danmaku, 'fun update(');
      expect(body, contains('items.size * 31'));
      expect(body, contains('items.first().timeMs'));
      expect(body, contains('items.last().timeMs'));
    });

    test('Kotlin 语法：isEmpty 必须带括号（CI 曾因此编译失败）', () {
      // Kotlin 的 isEmpty 是函数，不是属性——`items.isEmpty` 编译报
      // "Function invocation 'isEmpty()' expected"。
      final code = danmaku
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('items.isEmpty)')));
      expect(code, isNot(contains('items.isEmpty ')));
      expect(code, isNot(contains('items.isEmpty{')));
    });
  });

  group('⑤ MDK / Erika 路径未受影响', () {
    test('MDK 仍用 subtitleStyleWrites（subtitle.margin.y 像素）', () {
      expect(screen, contains('PlayerScreen.subtitleStyleWrites('));
      expect(screen, contains("(name: 'subtitle.margin.y', value: '\$marginY')"));
    });

    test('MDK 位图仍强制底部对齐', () {
      expect(screen, contains('forceBitmapBottom'));
      expect(screen, contains("'subtitle.alignment.y'"));
    });
  });
}

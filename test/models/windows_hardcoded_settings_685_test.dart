import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 685：Windows 上「视频路径」与「使用 Qt 播放器窗口」改为硬编码。
///
/// ## 为什么移除这两项
///
/// **视频路径**：Windows 只有 `surface` 可用——`texture` 路径会
/// `0xc0000005` 闪退（三次真机实证）。原设置页却给了下拉框，副标题还
/// 写着「请勿切换」——等于摆一个「点了就崩」的按钮。
///
/// **使用 Qt 播放器窗口**：Qt 窗口是 Windows 上唯一完整的播放器
/// （进度条 / 播放控制 / 音量 / 选集 / 音轨 / 字幕）。关掉只剩「有视频
/// 没控件」的裸窗口，没有任何合理场景。
///
/// ## 修复
///
/// 1. 设置页不再渲染这两项（Windows）
/// 2. 运行时硬编码：`effectiveMpvVideoOutput` 恒 surface、
///    `MpvSessionPlatform.qtPlayerEnabled` 恒 true
/// 3. `fromJson` 一次性清理旧值（加载后回写）
///
/// Android / 鸿蒙的「视频路径」保持可切换（Surface / 纹理都能跑）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String settingsModel;
  late String engineConfigScreen;
  late String sessionPlatform;
  late String playerScreen;
  late String mainDart;

  setUpAll(() {
    settingsModel = read('lib/models/app_settings.dart');
    engineConfigScreen = read('lib/screens/settings/engine_config_screen.dart');
    sessionPlatform = read('lib/services/player/mpv_session_platform.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
    mainDart = read('lib/main.dart');
  });

  /// 剔除注释行（注释里会提到旧写法，说明为什么改）。
  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  String extract(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var i = start;
    while (i < src.length && src[i] != '(') {
      i++;
    }
    var paren = 0;
    for (; i < src.length; i++) {
      if (src[i] == '(') paren++;
      if (src[i] == ')') {
        paren--;
        if (paren == 0) {
          i++;
          break;
        }
      }
    }
    while (i < src.length && src[i] != '{') {
      i++;
    }
    var depth = 0;
    for (; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  // ═══════════════════════════════════════════════════════════════
  // A. 视频路径：Windows 恒 surface
  // ═══════════════════════════════════════════════════════════════

  group('A 视频路径硬编码（Windows）', () {
    test('A1 Windows 恒返回 surface（无视配置值与 userSet）', () {
      // 配置是 texture + userSet=true 也必须被压回 surface
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'texture',
          userSet: true,
          platform: TargetPlatform.windows,
        ),
        'surface',
      );
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'surface',
          userSet: false,
          platform: TargetPlatform.windows,
        ),
        'surface',
      );
    });

    test('A2 Android/鸿蒙保持可配置（不误伤）', () {
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'texture',
          userSet: true,
          platform: TargetPlatform.android,
        ),
        'texture',
      );
      expect(
        AppSettings.effectiveMpvVideoOutput(
          'surface',
          userSet: true,
          platform: TargetPlatform.android,
        ),
        'surface',
      );
    });

    test('A3 源码：Windows 分支无条件 return surface', () {
      final body = extract(
          settingsModel, 'static String effectiveMpvVideoOutput(');
      final winIdx = body.indexOf('TargetPlatform.windows');
      expect(winIdx, greaterThan(0));
      final winBranch =
          body.substring(winIdx, (winIdx + 200).clamp(0, body.length));
      expect(winBranch, contains("return 'surface'"));
      // 旧写法是 `&& !userSet`（未手动设置才默认），必须已去掉
      expect(body, isNot(contains('TargetPlatform.windows &&')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. Qt 播放器：Windows 恒启用
  // ═══════════════════════════════════════════════════════════════

  group('B Qt 播放器硬编码（Windows）', () {
    test('B1 qtPlayerEnabled getter 在 Windows 恒 true', () {
      final body = extract(sessionPlatform, 'static bool get qtPlayerEnabled');
      expect(body, contains('Platform.isWindows ? true'));
    });

    test('B2 写入 false 被 getter 忽略（旧调用点无法关掉）', () {
      // setter 保留但只写私有字段；getter 在 Windows 直接返回 true
      expect(sessionPlatform, contains('static set qtPlayerEnabled('));
      final getter = extract(sessionPlatform, 'static bool get qtPlayerEnabled');
      expect(getter, contains('_qtPlayerEnabled'));
    });

    test('B3 播放页不再读 settings.useQtPlayer', () {
      final code = codeOnly(playerScreen);
      expect(code, isNot(contains('settings.useQtPlayer')));
      expect(code, isNot(contains('settingsProvider).useQtPlayer')));
      // 改为读平台常量
      expect(code, contains('MpvSessionPlatform.qtPlayerEnabled'));
    });

    test('B4 启动预热不再看设置（Windows 恒预热）', () {
      final code = codeOnly(mainDart);
      expect(code, isNot(contains('snapshot.useQtPlayer')));
      expect(code, contains('prewarmQtPlayer()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 设置页移除（Windows）
  // ═══════════════════════════════════════════════════════════════

  group('C 设置页不再渲染这两项（Windows）', () {
    test('C1 「视频路径」只在非 Windows 渲染', () {
      final body = extract(engineConfigScreen, 'List<Widget> _mpvChildren(');
      final idx = body.indexOf("title: '视频路径'");
      expect(idx, greaterThan(0), reason: 'Android/鸿蒙仍需展示');
      // 必须被 `!= windows` 条件包裹
      final before = body.substring(0, idx);
      expect(before, contains('defaultTargetPlatform != TargetPlatform.windows'));
    });

    test('C2 「使用 Qt 播放器窗口」整项已删除', () {
      // 剔除注释后判定（注释里会提到该项名称，说明为什么移除）
      final code = codeOnly(engineConfigScreen);
      expect(code, isNot(contains('使用 Qt 播放器窗口')));
      expect(code, isNot(contains('useQtPlayer')));
    });

    test('C3 不再有「请勿切换」这类摆着会崩的提示', () {
      expect(engineConfigScreen, isNot(contains('请勿切换')));
      expect(engineConfigScreen, isNot(contains('纹理路径在 Windows')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 旧配置迁移清理
  // ═══════════════════════════════════════════════════════════════

  group('D 旧配置一次性清理', () {
    test('D1 useQtPlayer 在 Windows 加载时被纠正为 true', () {
      final body = extract(settingsModel, 'factory AppSettings.fromJson(');
      expect(body, contains('useQtPlayer:'));
      expect(body, contains('TargetPlatform.windows'));
      // 必须有三元兜底，而不是直接读 json
      expect(body, isNot(contains("useQtPlayer: json['useQtPlayer'] as bool? ?? false")));
    });

    test('D2 mpvVideoOutput 在 Windows 迁移为 surface + userSet=false', () {
      final body = extract(
          settingsModel, 'static Map<String, Object> mpvTextureMigration(');
      expect(body, contains('TargetPlatform.windows'));
      final winIdx = body.indexOf('TargetPlatform.windows');
      final winBranch = body.substring(winIdx, winIdx + 300);
      expect(winBranch, contains("'mpvVideoOutput': 'surface'"));
      expect(winBranch, contains("'mpvVideoOutputUserSet': false"));
      expect(winBranch, contains("'mpvTextureAutoMigrated': true"));
    });

    test('D3 Windows 分支必须在 texture 迁移之前（先兜底再判旧值）', () {
      final body = extract(
          settingsModel, 'static Map<String, Object> mpvTextureMigration(');
      final winIdx = body.indexOf('TargetPlatform.windows');
      final texIdx = body.indexOf("stored == 'texture'");
      expect(winIdx, greaterThan(0));
      expect(texIdx, greaterThan(winIdx),
          reason: 'Windows 硬编码必须最先判定');
    });
  });
}

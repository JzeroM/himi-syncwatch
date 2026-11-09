import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 655：MPV 渲染器（`vo`）改为手动选择，删除 GLES 版本自动探测。
///
/// ## 为什么删除探测
///
/// 639 的 `_probeGlSupport()` 用 `queryGlEsVersion` 查驱动声明的版本号，
/// 再按 `major > 3 || (major == 3 && minor >= 1)` 决定 `gpu-next`/`gpu`。
///
/// 三个缺陷：
///
/// 1. **版本号不能预测可用性**。`vo=gpu-next` 能否跑起来取决于驱动实现
///    质量、扩展集、带宽等版本号无法反映的因素。640 提交说明自己也承认
///    「驱动可能虚报版本」——Mali-450 报告 GLES 3.1/3.2，但 mpv 自建
///    上下文仍然失败。
/// 2. **探测路径 ≠ 实际渲染路径**。探测用 1×1 pbuffer（EGL 配置里最宽松
///    的一种），mpv 实际用 ANativeWindow + 可能的 10bit 配置。
/// 3. **`eglTerminate` 有破坏进程 EGL 状态的风险**。探测用的
///    `EGL_DEFAULT_DISPLAY` 是进程级共享的（Flutter 引擎可能正在用）。
///
/// ## 现在的行为
///
/// `mpvRenderer` 三档：`auto`（等价 gpu-next）/ `gpu-next` / `gpu`。
/// 经 `AppSettings.resolveMpvVo()` 解析成实际 `vo` 值传给插件。
void main() {
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final platform = File(
    'lib/services/player/mpv_session_platform.dart',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final settingsScreen = File(
    'lib/screens/settings/engine_config_screen.dart',
  ).readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  group('① resolveMpvVo：纹理恒 gpu，Surface 按设置', () {
    test('纹理路径无视设置恒为 gpu', () {
      // media_kit 的 AndroidVideoController 走 TextureRegistry Surface +
      // wid + vo=gpu。传别的值会让 VideoOutput.Resize 永不触发 →
      // texture id 恒 null → 超时。
      for (final r in ['auto', 'gpu-next', 'gpu']) {
        expect(
          AppSettings.resolveMpvVo(renderer: r, nativeSurface: false),
          'gpu',
          reason: '纹理路径必须是 gpu（renderer=$r）',
        );
      }
    });

    test('Surface + auto → gpu-next（新设备默认）', () {
      expect(
        AppSettings.resolveMpvVo(renderer: 'auto', nativeSurface: true),
        'gpu-next',
      );
    });

    test('Surface + gpu-next → gpu-next', () {
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu-next', nativeSurface: true),
        'gpu-next',
      );
    });

    test('Surface + gpu → gpu（老 GPU 兼容档）', () {
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu', nativeSurface: true),
        'gpu',
      );
    });

    test('未知值按 auto 处理（不炸）', () {
      expect(
        AppSettings.resolveMpvVo(renderer: 'bogus', nativeSurface: true),
        'gpu-next',
      );
    });
  });

  group('② 设置项：默认 auto，非法值归一', () {
    test('构造器默认 auto', () {
      expect(const AppSettings().mpvRenderer, 'auto');
    });

    test('fromJson 缺字段 → auto', () {
      expect(AppSettings.fromJson(<String, dynamic>{}).mpvRenderer, 'auto');
    });

    test('fromJson 合法值保留', () {
      for (final v in ['auto', 'gpu-next', 'gpu']) {
        expect(
          AppSettings.fromJson(<String, dynamic>{'mpvRenderer': v}).mpvRenderer,
          v,
        );
      }
    });

    test('fromJson 非法值 → auto', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{'mpvRenderer': 'vulkan'})
            .mpvRenderer,
        'auto',
      );
    });

    test('toJson 往返保留', () {
      const s = AppSettings(mpvRenderer: 'gpu');
      expect(AppSettings.fromJson(s.toJson()).mpvRenderer, 'gpu');
    });

    test('copyWith 可改', () {
      expect(const AppSettings().copyWith(mpvRenderer: 'gpu').mpvRenderer, 'gpu');
    });

    test('标签三档齐全', () {
      expect(AppSettings.mpvRendererLabels.keys.toSet(),
          {'auto', 'gpu-next', 'gpu'});
    });
  });

  group('③ 插件侧：删除探测，接收 vo 参数', () {
    late String code;

    setUpAll(() => code = stripComments(android));

    test('不再有 GLES 探测相关符号', () {
      expect(code, isNot(contains('_probeGlSupport')));
      expect(code, isNot(contains('_glSupportsGpuNext')));
      expect(code, isNot(contains('_glProbed')));
      expect(code, isNot(contains('queryGlEsVersion')));
    });

    test('Kotlin 侧探测实现与通道分支一并删除（死代码清理）', () {
      final kt = File(
        'plugins/himi_mpv_android/android/src/main/kotlin/'
        'com/himi/mpv/android/HimiMpvAndroidPlugin.kt',
      ).readAsStringSync();
      // 方法体与 MethodChannel 分支都删掉，顺带消除
      // eglTerminate(EGL_DEFAULT_DISPLAY) 的隐患。
      expect(kt, isNot(contains('queryGlEsVersion')));
      expect(kt, isNot(contains('EGL14')));
      expect(kt, isNot(contains('GLES20')));
    });

    test('create 接受 vo 参数并落到 _voOverride', () {
      expect(code, contains('String vo = '));
      expect(code, contains('final String _voOverride;'));
      expect(code, contains('_voOverride = vo'));
    });

    test('_ensurePlayer 按 _voOverride 判定 gpu-next', () {
      expect(code, contains("_voOverride == 'gpu-next'"));
      expect(
        code,
        isNot(contains('major > 3 || (major == 3 && minor >= 1)')),
        reason: '版本阈值判据已删除',
      );
    });

    test('低端 GPU 补偿跟随手动选择', () {
      expect(code, contains("_voOverride == 'gpu'"));
      expect(code, contains("'framedrop': 'vo'"));
    });
  });

  group('④ 参数贯通：设置 → 适配器 → 会话工厂 → 插件', () {
    test('MpvSessionPlatform.create 接受 vo 并传给 Android 会话', () {
      expect(platform, contains('String vo = '));
      expect(platform, contains('vo: vo'));
    });

    test('适配器注入设置值', () {
      expect(adapter, contains('set mpvRenderer('));
      expect(adapter, contains('AppSettings.resolveMpvVo('));
    });

    test('播放页把 settings.mpvRenderer 写给适配器', () {
      expect(screen, contains('mpv.mpvRenderer = settings.mpvRenderer;'));
    });
  });

  group('⑤ 设置页有「渲染器」入口（仅 Android）', () {
    test('Android 才显示', () {
      expect(settingsScreen,
          contains('defaultTargetPlatform == TargetPlatform.android'));
      final idx = settingsScreen.indexOf("title: '渲染器'");
      expect(idx, greaterThan(-1));
    });

    test('文案说明遇到黑屏时手动切换', () {
      final idx = settingsScreen.indexOf("title: '渲染器'");
      final body = settingsScreen.substring(
        idx,
        (idx + 500).clamp(0, settingsScreen.length),
      );
      expect(body, contains('黑屏'));
      expect(body, contains('gpu（兼容）'));
    });

    test('选择后写回设置', () {
      expect(settingsScreen, contains('notifier.update(mpvRenderer: v)'));
    });
  });
}

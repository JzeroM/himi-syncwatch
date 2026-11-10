import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 639：四个真机问题的防回归。
///
/// 1. **安卓 TV 盒子（Mali-450 MP，GLES 3.0）surface 黑屏**——
///    `vo=gpu-next` 要求 GLES 3.1+，老 GPU 初始化失败 → 黑屏。
///    降级 `vo=gpu`（支持 ES 2.0+），代价是不支持 HDR 直出
///    （mpv 官方手册：`--target-colorspace-hint` 仅 `--vo=gpu-next`），
///    故对 HDR 内容启用 SDR tone mapping。
/// 2. **观众退房后房主人数未减**（两个方向都失败）——只依赖 `whoNow`，
///    而 `resolveOnlineCount` 在查询返回 0 时保留旧值。改为事件驱动集合。
/// 3. **Windows Surface 灰屏**（有声音/字幕，画面灰）——HWND 被 Flutter
///    不透明窗口遮挡。回退 texture。
/// 4. **Windows 从播放页返回闪退**——texture 路径下 Flutter 纹理随 widget
///    卸载立即销毁，而 150ms 延迟期间 mpv render context 仍在渲染。
void main() {
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final policy = File(
    'plugins/himi_mpv_core/lib/src/mpv_output_policy.dart',
  ).readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

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

  group('① 渲染器改为手动选择（655 取代 639 的 GLES 自动探测）', () {
    test('不再探测 GLES 版本', () {
      // 655：删除 `_probeGlSupport` / `_glSupportsGpuNext` / `_glProbed`。
      // 原因：版本号无法预测 gpu-next 能否真正跑起来（驱动可能虚报），
      // 且探测用 1×1 pbuffer 与实际 ANativeWindow 路径不同。
      final code = stripComments(android);
      expect(code, isNot(contains('_probeGlSupport')));
      expect(code, isNot(contains('_glSupportsGpuNext')));
      expect(code, isNot(contains('_glProbed')));
    });

    test('vo 由构造参数决定（不再按版本判定）', () {
      expect(android, contains('final String _voOverride;'));
      final body =
          stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, contains("_voOverride == 'gpu-next'"));
      expect(
        body,
        isNot(contains('major > 3 || (major == 3 && minor >= 1)')),
        reason: '版本阈值判据已删除',
      );
    });

    test('vo 按能力选择 gpu-next / gpu', () {
      expect(
        android,
        contains("if (effectiveSurface) 'vo': useGpuNext ? 'gpu-next' : 'gpu'"),
      );
    });

    test('HDR 直出只在 gpu-next 时写入', () {
      final body = stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, contains('if (hdr && effectiveSurface && useGpuNext)'));
      expect(body, contains("'target-colorspace-hint': 'yes'"));
    });

    test('非 gpu-next 的 HDR 内容走 SDR tone mapping', () {
      final body = stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, contains('if (hdr && effectiveSurface && !useGpuNext)'));
      expect(body, contains("'tone-mapping': 'spline'"));
      expect(body, contains("'target-prim': 'bt.709'"));
      expect(body, contains("'target-trc': 'srgb'"));
    });

    test('纹理模式跳过探测（本就不涉及 gpu-next）', () {
      final body = bodyOf(android, 'Future<void> _start() async {');
      expect(body, isNot(contains('_probeGlSupport')));
      expect(body, contains('if (!nativeSurface)'));
    });

    test('设置项 resolveMpvVo：纹理恒 gpu，Surface 按设置', () {
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu', nativeSurface: false),
        'gpu',
      );
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu-next', nativeSurface: false),
        'gpu',
        reason: '纹理路径必须 gpu，否则纹理 id 永不注册',
      );
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu', nativeSurface: true),
        'gpu',
      );
      expect(
        AppSettings.resolveMpvVo(renderer: 'auto', nativeSurface: true),
        'gpu-next',
      );
      expect(
        AppSettings.resolveMpvVo(renderer: 'gpu-next', nativeSurface: true),
        'gpu-next',
      );
    });
  });

  group('② 人数：事件驱动成员集合', () {
    test('新增 _onlineUserIds 集合', () {
      expect(screen, contains('final Set<String> _onlineUserIds = <String>{};'));
    });

    test('join / 心跳 驱动 _onUserJoined', () {
      expect(screen, contains('_onUserJoined(message[\'userId\'] as String?)'));
      final body = stripComments(bodyOf(screen, 'void _onUserJoined(String? userId) {'));
      expect(body, contains('_onlineUserIds.add(userId)'));
      expect(body, contains('_onlineUserCount = _onlineUserIds.length'));
    });

    test('leave 驱动 _onUserLeft（立即生效）', () {
      expect(screen, contains('_onUserLeft(message[\'userId\'] as String?)'));
      final body = stripComments(bodyOf(screen, 'void _onUserLeft(String? userId) {'));
      expect(body, contains('_onlineUserIds.remove(userId)'));
      expect(
        body,
        contains('if (userId == _myUserId) return;'),
        reason: '自己不能被移除，否则房主会出现 0 人',
      );
    });

    test('presence 事件同样驱动集合', () {
      expect(screen, contains('_onUserJoined(publisher)'));
      expect(screen, contains('_onUserLeft(publisher)'));
    });

    test('_refreshOnlineCount 用 ids 校准、空结果不清空', () {
      final body =
          stripComments(bodyOf(screen, 'void _refreshOnlineCount(RtmService rtmService) async {'));
      expect(body, contains('getOnlineUserIds'));
      expect(body, contains('if (ids.isNotEmpty)'));
      expect(body, contains('_applyOnlineUsers(ids)'));
      expect(
        body,
        isNot(contains('resolveOnlineCount')),
        reason: '旧实现在查询返回 0 时保留旧值 → 人数永不下降',
      );
    });

    test('_applyOnlineUsers 始终把自己加回集合', () {
      final body =
          stripComments(bodyOf(screen, 'void _applyOnlineUsers(Iterable<String> ids) {'));
      expect(body, contains('next.add(me)'));
    });

    test('初始化时把自己加入集合', () {
      expect(screen, contains('_onlineUserIds.add(me)'));
    });
  });

  group('③ Windows 默认 Surface（656：646 顶层窗口已解决灰屏）', () {
    test('策略层 Windows 默认 surface', () {
      final body = stripComments(bodyOf(
        policy,
        'static String effectiveVideoOutput({\n    required String configured,\n    required bool userSet,\n    required bool windows,\n  }) {',
      ));
      // 656：639 的 texture 默认值已过时。646 用原生顶层窗口解决了
      // 「子 HWND 被 Flutter 不透明层遮挡」的灰屏根因，647 真机已验证
      // HDR 直出成功。647 只改了 AppSettings（设置页显示）漏了本函数，
      // 导致「设置页显示 Surface、实际走 texture」——新用户 HDR 用不上。
      expect(body, contains('if (windows && !userSet) return surface;'));
    });

    test('显式选纹理时仍尊重用户配置', () {
      final body = stripComments(bodyOf(
        policy,
        'static String effectiveVideoOutput({\n    required String configured,\n    required bool userSet,\n    required bool windows,\n  }) {',
      ));
      expect(body, contains('normalizeVideoOutput(configured)'));
    });
  });

  group('④ Windows 返回闪退：不做 150ms 延迟（643 扩展为全引擎）', () {
    test('Windows 下所有引擎都立即 dispose（不再只特判 MPV）', () {
      final body = stripComments(bodyOf(
        screen,
        'Future<void> _disposePlayerAfterDelay(PlayerAdapter player) async {',
      ));
      // 643：旧实现只让 MPV 不延迟，MDK 仍等 150ms —— 反而更危险
      // （widget 树早已卸载，150ms 后才注销纹理 → 撞上已释放资源）。
      // 现在 Windows 全引擎统一不延迟，时序由 _safePopPlayerPage 保证。
      expect(
        body,
        contains('defaultTargetPlatform != TargetPlatform.windows'),
        reason: '非 Windows 才延迟；Windows 一律立即释放',
      );
      expect(
        body,
        isNot(contains('isWindowsMpv')),
        reason: '按引擎特判已移除（MDK 同样崩溃，偏移一致）',
      );
    });

    test('退出前先卸视频层（_safePopPlayerPage）', () {
      final body = stripComments(bodyOf(
        screen,
        'Future<void> _safePopPlayerPage({bool popUntilFirst = false}) async {',
      ));
      expect(body, contains('_videoLayerDetached = true'));
      expect(body, contains('endOfFrame'));
      expect(body, contains('Navigator.pop(context)'));
    });
  });
}

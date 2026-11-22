import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 695 追补守卫：
/// - F：MPV 缓冲双滑杆（三端统一默认 200MB/30s；698 N12-D 防 TV 低内存杀）
///   + load 前统一下发 + TV 保护上限；
/// - A：网速 1s tick 走轻量 statePatch（「跑一秒停顿一下」根因）；
/// - E：鸿蒙详情面板可滚动（真机回归）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  final screen = read('lib/screens/player/player_screen.dart');
  final adapter = read('lib/services/player/qt_player_adapter.dart');
  final mainCpp =
      read('native/windows_qt_player/src/main.cpp');
  final engineCfg = read('lib/screens/settings/engine_config_screen.dart');
  final ohosPlugin = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvOhosPlugin.ets');
  final ohosPanel = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerPanel.ets');

  group('① F 缓冲双滑杆（默认 200MB/30s 三端统一，698 N12-D）', () {
    test('AppSettings 默认值与钳位', () {
      const s = AppSettings();
      expect(s.mpvMaxBufferMb, 200,
          reason: '698 N12-D：TV 低内存闪退（LMK）风险项，500→200');
      expect(s.mpvMaxBufferSecs, 30);
      final j = AppSettings.fromJson(
          const {'mpvMaxBufferMb': 99999, 'mpvMaxBufferSecs': 1});
      expect(j.mpvMaxBufferMb, 2048, reason: '上限钳位 2048');
      expect(j.mpvMaxBufferSecs, 5, reason: '下限钳位 5');
    });

    test('load 前统一写入 demuxer-max-bytes/半值 back/cache-secs', () {
      expect(screen, contains("'demuxer-max-bytes'"));
      expect(screen, contains("'demuxer-max-back-bytes'"));
      expect(screen, contains("'cache-secs'"));
      expect(screen, contains('settings.mpvMaxBufferMb'),
          reason: '写入值跟随滑杆设置');
    });

    test('TV 保护上限（698 N12-D）：TV 模式缓冲钳 200MB/30s', () {
      expect(screen, contains('TV 缓冲保护上限'),
          reason: 'TV 盒低内存：卡住时 500MB 缓存涨满 = LMK 杀进程闪退');
      expect(screen, contains('settings.mpvMaxBufferMb > 200'));
      expect(screen, contains('settings.mpvMaxBufferSecs > 30'));
    });

    test('设置页两个滑杆（TV 遥控：settingsTvSliderRow 既有范式）', () {
      expect(engineCfg, contains("sliderKey: 'mpvMaxBufferMb'"));
      expect(engineCfg, contains("sliderKey: 'mpvMaxBufferSecs'"));
      expect(engineCfg, contains('settingsTvSliderRow('),
          reason: 'TV 整行聚焦 + 左右键 ±step（settings_common 既有）');
    });

    test('鸿蒙 native 硬编码对齐 200/100MiB（698 N12-D）', () {
      expect(ohosPlugin, isNot(contains("'500MiB'")));
      expect(ohosPlugin, contains("'200MiB'"));
      expect(ohosPlugin, contains("'100MiB'"));
    });
  });

  group('⑥ N12 TV 卡死防闪退（遥控可靠性，698）', () {
    test('遥控全局兜底：HardwareKeyboard 注册/注销成对', () {
      expect(screen,
          contains('HardwareKeyboard.instance.addHandler(_tvGlobalKeyGuard)'));
      expect(screen,
          contains('HardwareKeyboard.instance.removeHandler(_tvGlobalKeyGuard)'));
    });

    test('兜底语义：控件隐藏时 OK/上/下 必达唤出（与焦点无关）', () {
      expect(screen, contains('_tvGlobalKeyGuard'));
      expect(screen, contains('_showControlsForTv();'),
          reason: '隐藏时直接唤出；已显示放行焦点链不抢按钮');
    });

    test('遥控路径防逃逸护栏：异常落 FATAL 不闪退', () {
      expect(screen, contains('_guardedRun('), reason: 'PlayerHotkey 回调全包护栏');
      expect(screen, contains('遥控[\$what]异常'));
    });

    test('重载竞态防护：inFlight 忽略播放/暂停与快进退', () {
      expect(screen, contains('重载进行中，忽略播放/暂停'));
      expect(screen, contains('重载进行中，忽略快进退'));
    });

    test('按键留痕（N12-E 闪退取证：himi_runtime.log 最后按键序列）', () {
      expect(screen, contains('TV按键 '));
    });
  });

  group('② A 网速 1s tick 走轻量 statePatch（跑一秒停顿一下 根因）', () {
    test('Qt 适配器 pushStatePatch + C++ statePatch 命令', () {
      expect(adapter, contains('void pushStatePatch('));
      expect(mainCpp, contains('QLatin1String("statePatch")'));
      expect(mainCpp, contains('state.applyJson('),
          reason: 'patch 并入 PlayerState（既有机制）');
    });

    test('player_screen 网速分支走 patch（Qt），不再全量推送', () {
      final i = screen.indexOf("'networkSpeedText': text");
      expect(i, greaterThan(0));
      final branch = screen.substring(i - 400, i + 50);
      expect(branch, contains('pushStatePatch'),
          reason: '1Hz 网速变化不得触发全量 _syncNativePanelData');
    });
  });

  group('④ 弹幕自绘 + 占位常驻 + 时钟减顿挫（695 渲染换代收尾）', () {
    test('占位门双保险 + firstFrameRendered 接线（播放中不再挂占位）', () {
      final overlay =
          read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay,
          contains('!(playerState.playerReady || playerState.durationMs > 0)'),
          reason: 'playerReady（首帧置位）或有片源即隐占位');
      expect(mainCpp, contains('MpvWindow::firstFrameRendered'),
          reason: '首帧信号 → playerReady:true（此前信号是死的）');
    });

    test('弹幕时钟软同步节流 + 死区放宽（跑一秒停顿一下 残余）', () {
      final state = read('native/windows_qt_player/src/player_state.cpp');
      expect(state, contains('dmSoftSyncTimer_'), reason: '软同步 ≥250ms 节流');
      expect(state, contains('err > 80 || err < -80'), reason: '死区 40→80');
    });

    test('自绘渲染器注册 + CMake 源清单', () {
      expect(mainCpp, contains('qmlRegisterType<DanmakuPaintItem>'));
      final cmake = read('native/windows_qt_player/CMakeLists.txt');
      expect(cmake, contains('src/danmaku_paint_item.cpp'));
      final paint =
          read('native/windows_qt_player/src/danmaku_paint_item.cpp');
      expect(paint, contains('DanmakuPaintItem::paint(QPainter'));
    });
  });

  group('⑤ 驱动链减负（696：跑一秒停顿一下 GC 根治）', () {
    test('tick 每帧零分配：投影挪进 paint()（安卓 Canvas 同构）', () {
      final layer = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
      // 每帧只写一个 qint64；x/y/alpha/渐隐全在 C++ 现算。
      expect(layer, contains('paintLayer.positionMs = pos'),
          reason: '每帧唯一写入——不再 out.push N 个 JS 对象 + QVariantList 深转换');
      expect(layer, isNot(contains('frameItems = out')),
          reason: '每帧 N 对象分配 = GC 垃圾，周期性回收停顿');
      final paint =
          read('native/windows_qt_player/src/danmaku_paint_item.cpp');
      expect(paint, contains('positionMs_ - timeMs'),
          reason: '投影公式在 paint() 内按 positionMs 现算');
    });

    test('NOTIFY 拆分：位置 20Hz 与 mediaInfoJson 不再拖重型绑定', () {
      final h = read('native/windows_qt_player/src/player_state.h');
      expect(h,
          contains('Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY positionTick)'));
      expect(h,
          contains('Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY positionTick)'));
      expect(h,
          contains('Q_PROPERTY(qint64 bufferedMs READ bufferedMs NOTIFY positionTick)'));
      expect(h, contains('NOTIFY\n                   mediaInfoChanged'),
          reason: 'mediaInfoJson 独立信号——JSON.parse 绑定只随内容真变重算');
      final cpp = read('native/windows_qt_player/src/player_state.cpp');
      expect(cpp, contains('if (posDirty) emit positionTick();'));
      expect(cpp, contains('if (mediaDirty) emit mediaInfoChanged();'));
    });

    test('弹幕增量推送 + reset 全量重建（不再 500ms 整窗重推）', () {
      expect(screen, contains('_qtDanmakuPushedKeys'));
      expect(screen, contains('if (sig == _lastQtDanmakuSig) return;'));
      final cpp = read('native/windows_qt_player/src/player_state.cpp');
      expect(cpp, contains('if (same && !reset) return;'),
          reason: '批次相等短路（reset 必须放行——epoch 递增不能漏）');
    });
  });

  group('③ E 鸿蒙详情面板可滚动（真机回归）', () {
    test('MediaInfoContent 包 Scroll 纵向滚动', () {
      final i = ohosPanel.indexOf('MediaInfoContent() {');
      expect(i, greaterThan(0));
      final body = ohosPanel.substring(i, i + 200);
      expect(body, contains('Scroll()'));
      expect(ohosPanel, contains('.scrollable(ScrollDirection.Vertical)'));
    });
  });
}

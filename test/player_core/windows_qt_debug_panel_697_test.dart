import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：Windows Qt 播放调试面板（`DebugPanel.qml` + `player_state` 字段贯通）。
///
/// ## 为什么需要这组测试
///
/// Windows 是唯一能跑完整 libplacebo 杜比视界处理的平台（D3D11 compute），
/// 而 Flutter 播放页在 Qt 模式下已退场——DV/HDR 排查全靠这块 QML 面板。
/// 一旦「字段名对不上」或「面板没挂进 Overlay」，真机就是一片空白，
/// 而这类问题**无法靠 Dart 单测发现**（跨了 QML/C++ 边界）。
///
/// ## 覆盖的三段链路
///
/// | 段 | 文件 | 风险 |
/// |---|---|---|
/// | 采集 → 下发 | `mpv_player_adapter.dart` / `player_screen.dart` | 键名写错 → Qt 收到空值 |
/// | 下发 → 状态 | `native_player_state.dart` → `player_state.cpp` | JSON 键漏解析 → 恒为默认值 |
/// | 状态 → UI | `player_state.h` Q_PROPERTY → `DebugPanel.qml` | 属性没注册 → QML 绑定失败 |
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String panelQml;
  late String debugRowQml;
  late String groupHeaderQml;
  late String overlayQml;
  late String cmake;
  late String stateH;
  late String stateCpp;
  late String adapterDart;
  late String playerScreen;
  late String nativeState;
  late String sessionDart;

  setUpAll(() {
    panelQml = read('$dir/src/qml/DebugPanel.qml');
    debugRowQml = read('$dir/src/qml/DebugRow.qml');
    groupHeaderQml = read('$dir/src/qml/DebugGroupHeader.qml');
    overlayQml = read('$dir/src/qml/Overlay.qml');
    cmake = read('$dir/CMakeLists.txt');
    stateH = read('$dir/src/player_state.h')
        // Q_PROPERTY 可能跨行声明（长属性名），压成单行便于断言
        .replaceAll(RegExp(r'\s+'), ' ');
    stateCpp = read('$dir/src/player_state.cpp');
    adapterDart = read('lib/services/player/mpv_player_adapter.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
    nativeState = read('lib/services/player/native/native_player_state.dart');
    sessionDart = read('lib/services/player/qt_player_session.dart');
  });

  group('1. 面板文件与构建注册', () {
    test('1.1 三个 QML 文件都存在且可被 CMake 打包', () {
      for (final f in ['DebugPanel', 'DebugRow', 'DebugGroupHeader']) {
        expect(File('$dir/src/qml/$f.qml').existsSync(), isTrue,
            reason: '$f.qml 不存在');
        // QML_FILES 里必须列出，否则 qrc 里没有 → 运行时 import 失败
        expect(cmake, contains('src/qml/$f.qml'), reason: '$f 未加入 QML_FILES');
        // QT_RESOURCE_ALIAS 的 foreach 列表也必须包含
        expect(cmake, contains(f), reason: '$f 未设置 RESOURCE_ALIAS');
      }
    });

    test('1.2 不使用内联组件（不共享外层作用域，拿不到 root 辅助函数）', () {
      // QML 的 `component X: Item {}` 与外层文档作用域隔离，
      // 引用 root/contentColumn 会在运行时静默失效。
      expect(panelQml, isNot(contains('component DebugRow:')));
      expect(panelQml, isNot(contains('component DebugGroupHeader:')));
      // 独立组件用属性通信
      expect(debugRowQml, contains('property string label:'));
      expect(debugRowQml, contains('property string value:'));
      expect(debugRowQml, contains('property string severity:'));
      expect(groupHeaderQml, contains('property string title:'));
      expect(groupHeaderQml, contains('signal toggleRequested()'));
    });

    test('1.2 面板挂载在 Overlay 且绑定 showDebug', () {
      expect(overlayQml, contains('DebugPanel {'));
      expect(overlayQml, contains('shown: playerState.showDebug'));
    });

    test('1.3 面板是半透明可拖动（不是实心黑底）', () {
      // 半透明：alpha 0.72（旧 Flutter 面板 0.92 太实，挡住画面）
      expect(panelQml, contains('Qt.rgba(0, 0, 0, 0.72)'));
      expect(panelQml, isNot(contains('Qt.rgba(0, 0, 0, 0.92)')));
      // 拖动：标题栏 MouseArea 改 panelX/panelY
      expect(panelQml, contains('root.panelX += mouse.x - pressX'));
      expect(panelQml, contains('root.panelY += mouse.y - pressY'));
      expect(panelQml, contains('Qt.SizeAllCursor'));
    });

    test('1.4 锁定态隐藏（四端一致）', () {
      expect(panelQml, contains('&& !playerState.locked'));
    });

    test('1.4b font.pixelSize 必须是整数（10.5 → Overlay 加载失败）', () {
      // QML 的 `font.pixelSize` 类型是 int；写 10.5 会报
      // 「Invalid property assignment: int expected」，
      // 且**整个 Overlay 加载失败** → 装机后启动即回退。
      for (final src in [panelQml, debugRowQml, groupHeaderQml]) {
        expect(
          RegExp(r'pixelSize:\s*\d+\.\d+').hasMatch(src),
          isFalse,
          reason: 'font.pixelSize 不接受小数',
        );
      }
    });

    test('1.5 关闭按钮不破坏 shown 绑定', () {
      // 直接写 shown = false 会打断绑定，导致设置里重开无效
      expect(panelQml, contains('root.dismissed = true'));
      expect(panelQml, isNot(contains('root.shown = false')));
      // 重新打开时复位
      expect(panelQml, contains('if (shown) dismissed = false'));
    });
  });

  group('2. 五个分组齐全（HDR/DV 为排查重点）', () {
    test('2.1 分组标题', () {
      expect(panelQml, contains('title: "播放"'));
      expect(panelQml, contains('title: "HDR 输入"'));
      expect(panelQml, contains('title: "HDR 输出"'));
      expect(panelQml, contains('title: "杜比视界"'));
      expect(panelQml, contains('title: "渲染管线"'));
    });

    test('2.2 HDR 输入/输出/DV 分组高亮', () {
      // 三个关键分组必须 highlighted（主色标题，排查时一眼定位）
      final inputIdx = panelQml.indexOf('title: "HDR 输入"');
      final inputBlock = panelQml.substring(inputIdx, inputIdx + 200);
      expect(inputBlock, contains('highlighted: true'));

      final outputIdx = panelQml.indexOf('title: "HDR 输出"');
      final outputBlock = panelQml.substring(outputIdx, outputIdx + 200);
      expect(outputBlock, contains('highlighted: true'));

      final dvIdx = panelQml.indexOf('title: "杜比视界"');
      final dvBlock = panelQml.substring(dvIdx, dvIdx + 200);
      expect(dvBlock, contains('highlighted: true'));
    });

    test('2.3 分组可折叠', () {
      expect(panelQml, contains('function isCollapsed(key)'));
      expect(panelQml, contains('function toggle(key)'));
      expect(groupHeaderQml, contains('signal toggleRequested()'));
      // 折叠状态需整体替换才触发 QML var 属性通知
      expect(panelQml, contains('root.collapsedMap = m'));
    });
  });

  group('3. 状态色语义（异常必须一眼看出）', () {
    test('3.1 四档颜色（DebugRow.severityColor）', () {
      expect(debugRowQml, contains('if (sev === "good") return "#6EE7A0"'));
      expect(debugRowQml, contains('if (sev === "warn") return "#FBBF24"'));
      expect(debugRowQml, contains('if (sev === "error") return "#F87171"'));
    });

    test('3.2 DV 未识别报红', () {
      expect(
        panelQml,
        contains('severity: playerState.dvContent ? "good" : "error"'),
      );
    });

    test('3.3 DV 用错 tone-mapping 报红', () {
      // 697 修复点：DV 必须 bt.2390，否则高光细节丢失
      expect(
        panelQml,
        contains('root.isDv() && playerState.toneMapping !== "bt.2390"'),
      );
    });

    test('3.4 P5 + 后端不支持 DV 报红', () {
      expect(panelQml, contains('playerState.doviProfile === 5'));
      expect(panelQml, contains('P5 风险'));
      expect(panelQml, contains('后端不支持 DV，画面会偏色'));
    });

    test('3.5 丢帧阈值分级', () {
      expect(panelQml, contains('playerState.frameDropCount > 100'));
      expect(panelQml, contains('playerState.frameDropCount > 10'));
    });
  });

  group('4. 后端 DV 能力判定', () {
    test('4.1 D3D11 / Vulkan 视为支持，OpenGL ES 不支持', () {
      expect(panelQml, contains('function backendSupportsDv()'));
      expect(panelQml, contains('ctx.indexOf("d3d11") >= 0'));
      expect(panelQml, contains('ctx.indexOf("vulkan") >= 0'));
    });

    test('4.2 判定依据是 gpuContext（不是 gpuApi）', () {
      // libplacebo 的 DV 处理靠 compute shader，取决于 context 而非 api
      final idx = panelQml.indexOf('function backendSupportsDv()');
      final block = panelQml.substring(idx, idx + 300);
      expect(block, contains('playerState.gpuContext'));
    });
  });

  group('5. HDR 输出判定', () {
    test('5.1 target-trc 为 pq/hlg 才算 HDR 输出', () {
      expect(panelQml, contains('function isHdrOut()'));
      final idx = panelQml.indexOf('function isHdrOut()');
      final block = panelQml.substring(idx, idx + 200);
      expect(block, contains('playerState.targetTrc'));
      expect(block, contains('"pq"'));
      expect(block, contains('"hlg"'));
    });
  });

  group('6. Q_PROPERTY 注册完整（否则 QML 绑定静默失败）', () {
    test('6.1 HDR/DV 字段全部注册', () {
      const props = [
        'videoParamsPrimaries',
        'videoParamsGamma',
        'videoParamsSigPeak',
        'videoParamsBitDepth',
        'videoParamsPixelFormat',
        'doviProfile',
        'doviLevel',
        'dvContent',
        'targetPrim',
        'targetTrc',
        'toneMapping',
        'toneMappingMode',
        'hdrComputePeak',
        'currentVo',
        'gpuApi',
        'gpuContext',
        'estimatedVfFps',
        'frameDropCount',
        'decoderFrameDropCount',
        'hwdecCurrent',
        'videoFormat',
        'showDebug',
        'bufferedMs',
      ];
      for (final p in props) {
        expect(
          stateH.contains('READ $p NOTIFY changed'),
          isTrue,
          reason: '$p 没有注册 Q_PROPERTY READ ... NOTIFY changed',
        );
      }
    });

    test('6.2 每个 Q_PROPERTY 都有 getter 实现', () {
      const getters = [
        'QString videoParamsPrimaries() const',
        'QString videoParamsGamma() const',
        'double videoParamsSigPeak() const',
        'int videoParamsBitDepth() const',
        'QString videoParamsPixelFormat() const',
        'int doviProfile() const',
        'int doviLevel() const',
        'bool dvContent() const',
        'QString targetPrim() const',
        'QString targetTrc() const',
        'QString toneMapping() const',
        'QString toneMappingMode() const',
        'QString hdrComputePeak() const',
        'QString currentVo() const',
        'QString gpuApi() const',
        'QString gpuContext() const',
        'double estimatedVfFps() const',
        'int frameDropCount() const',
        'int decoderFrameDropCount() const',
        'QString hwdecCurrent() const',
        'QString videoFormat() const',
        'bool showDebug() const',
        'qint64 bufferedMs() const',
      ];
      for (final g in getters) {
        expect(stateH.contains(g), isTrue, reason: '缺 getter: $g');
      }
    });

    test('6.3 所有属性走同一个 NOTIFY changed（QML 才能刷新）', () {
      // 用单一 changed 信号：applyJson 末尾统一 emit，简单可靠
      final hdrProps = [
        'videoParamsPrimaries',
        'doviProfile',
        'targetTrc',
        'gpuContext',
        'showDebug',
      ];
      for (final p in hdrProps) {
        expect(stateH.contains('READ $p NOTIFY changed'), isTrue,
            reason: '$p 必须 NOTIFY changed');
      }
    });
  });

  group('7. applyJson 解析完整（漏解析 = 恒为默认值）', () {
    test('7.1 全部 HDR/DV 键都有 readString/readDouble/readInt64/readBool', () {
      const keys = [
        'videoParamsPrimaries',
        'videoParamsGamma',
        'videoParamsSigPeak',
        'videoParamsBitDepth',
        'videoParamsPixelFormat',
        'doviProfile',
        'doviLevel',
        'dvContent',
        'targetPrim',
        'targetTrc',
        'toneMapping',
        'toneMappingMode',
        'hdrComputePeak',
        'currentVo',
        'gpuApi',
        'gpuContext',
        'estimatedVfFps',
        'frameDropCount',
        'decoderFrameDropCount',
        'hwdecCurrent',
        'videoFormat',
        'showDebug',
      ];
      for (final k in keys) {
        expect(stateCpp.contains('"$k"'), isTrue, reason: 'applyJson 缺 $k');
      }
    });

    test('7.2 bufferedMs 解析', () {
      expect(stateCpp, contains('"bufferedMs"'));
      expect(stateCpp, contains('bufferedMs_'));
    });

    test('7.3 数值字段用正确读取函数', () {
      // double 字段不能用 readInt64（会截断）
      expect(stateCpp, contains('readDouble(json, "videoParamsSigPeak"'));
      expect(stateCpp, contains('readDouble(json, "estimatedVfFps"'));
      // int 字段用 readInt64 + static_cast
      expect(stateCpp, contains('readInt64(json, "doviProfile"'));
      expect(stateCpp, contains('readInt64(json, "frameDropCount"'));
      // bool 字段用 readBool
      expect(stateCpp, contains('readBool(json, "dvContent"'));
      expect(stateCpp, contains('readBool(json, "showDebug"'));
    });
  });

  group('8. Dart 侧下发链路', () {
    test('8.1 NativePlayerState 有对应字段', () {
      const fields = [
        'videoParamsPrimaries',
        'videoParamsGamma',
        'videoParamsSigPeak',
        'videoParamsBitDepth',
        'videoParamsPixelFormat',
        'doviProfile',
        'doviLevel',
        'dvContent',
        'targetPrim',
        'toneMapping',
        'toneMappingMode',
        'hdrComputePeak',
        'gpuApi',
        'gpuContext',
        'estimatedVfFps',
        'frameDropCount',
        'decoderFrameDropCount',
        'videoFormat',
      ];
      for (final f in fields) {
        // 构造参数 / 字段 / fromJson / toJson / copyWith 至少各出现一次
        expect(nativeState.contains('this.$f'), isTrue,
            reason: 'NativePlayerState 缺构造参数 $f');
        expect(nativeState.contains('final '), isTrue);
        expect(nativeState.contains("'$f': $f"), isTrue,
            reason: 'toJson 缺 $f');
        expect(nativeState.contains("json['$f']"), isTrue,
            reason: 'fromJson 缺 $f');
      }
    });

    test('8.2 适配器填充 HDR/DV 指标', () {
      expect(adapterDart, contains('videoParamsPrimaries: _colorInfo?.primaries'));
      expect(adapterDart, contains('videoParamsGamma: _colorInfo?.gamma'));
      expect(adapterDart, contains('doviProfile: _colorInfo?.doviProfile'));
      expect(adapterDart, contains('dvContent: _dvContentForMedia'));
      expect(adapterDart, contains("targetPrim: _debugProps['target-prim']"));
      expect(adapterDart, contains("toneMapping: _debugProps['tone-mapping']"));
    });

    test('8.3 readDebugProperties 缓存 video-params 解析结果', () {
      expect(adapterDart, contains('Future<Map<String, String>> readDebugProperties'));
      expect(adapterDart, contains('_colorInfo = VideoColorInfo.tryParse(vp)'));
      expect(adapterDart, contains('Map<String, String> get debugProps'));
      expect(adapterDart, contains('VideoColorInfo? get colorInfo'));
    });

    test('8.4 Qt 会话定时推送调试指标', () {
      expect(sessionDart, contains('collectDebugMetrics'));
      expect(sessionDart, contains('_debugTimer'));
      expect(sessionDart, contains('Duration(seconds: 1)'));
      // shutdown 必须清定时器（否则会话销毁后仍在跑）
      final shutdownIdx = sessionDart.indexOf('void shutdown()');
      final shutdownBlock = sessionDart.substring(shutdownIdx);
      expect(shutdownBlock, contains('_debugTimer?.cancel()'));
    });

    test('8.5 播放页注入采集回调', () {
      expect(playerScreen,
          contains('session.collectDebugMetrics = _collectQtDebugMetrics'));
      expect(playerScreen,
          contains('Future<Map<String, Object?>?> _collectQtDebugMetrics()'));
    });

    test('8.5b 补丁含 bufferedMs（页面 pop 后唯一数据源）', () {
      // 页面存活时 `_syncNativePanelData` 推完整快照；pop 后只剩这条
      // 1s 补丁 → 缓冲进度必须跟着走，否则面板冻结在接管瞬间。
      expect(playerScreen, contains("'bufferedMs': p.buffered()"));
    });

    test('8.6 面板关闭时不采集（省 IPC）', () {
      // 采集一次要直读 14 个 mpv 属性（跨进程）。面板关着还每秒读是浪费。
      expect(sessionDart, contains('bool Function()? isDebugEnabled'));
      expect(sessionDart, contains('if (enabled != null && !enabled()) return;'));
      expect(playerScreen, contains('session.isDebugEnabled = () =>'));
      expect(playerScreen, contains('ref.read(settingsProvider).showSyncDebug'));
    });
  });

  group('9. 一键复制对齐 Flutter 面板格式', () {
    test('9.1 输出「## 分组」+「标签: 值」', () {
      expect(panelQml, contains('function plainText()'));
      expect(panelQml, contains('lines.push("## " + t)'));
      expect(panelQml, contains('lines.push(label + ": " + value)'));
    });

    test('9.2 复制内容覆盖五个分组', () {
      final idx = panelQml.indexOf('function plainText()');
      final block = panelQml.substring(idx, idx + 3000);
      for (final s in ['播放', 'HDR 输入', 'HDR 输出', '杜比视界', '渲染管线']) {
        expect(block, contains('sec("$s")'), reason: '复制缺分组 $s');
      }
    });

    test('9.3 不依赖子项遍历（折叠时会漏项）', () {
      final idx = panelQml.indexOf('function plainText()');
      final block = panelQml.substring(idx, idx + 3000);
      expect(block, isNot(contains('contentColumn.children')));
    });
  });

  group('10. 旧面板彻底移除', () {
    test('10.1 sync_debug_panel.dart 已删除', () {
      expect(
        File('lib/screens/player/widgets/sync_debug_panel.dart').existsSync(),
        isFalse,
      );
    });

    test('10.2 播放页不再引用旧面板', () {
      expect(playerScreen, isNot(contains('SyncDebugPanel')));
      expect(playerScreen, isNot(contains('sync_debug_panel.dart')));
    });

    test('10.3 播放页挂的是新面板', () {
      expect(playerScreen, contains('PlaybackDebugPanel('));
      expect(playerScreen, contains('debug_metrics_collector.dart'));
    });

    test('10.4 Flutter 面板也遵循锁定态', () {
      // 四端一致：锁定后只留锁钮，面板不该还挂在画面上
      expect(
        playerScreen,
        contains('ref.watch(settingsProvider).showSyncDebug &&'),
      );
      expect(playerScreen, contains('!_lockController.locked)'));
    });
  });
}

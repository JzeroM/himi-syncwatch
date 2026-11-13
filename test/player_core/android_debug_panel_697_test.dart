import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：安卓原生调试面板（`DebugPanelView` + `DebugPanelFormat`）静态检查。
///
/// ## 为什么用 Dart 测 Kotlin
///
/// 本仓库没有 gradle wrapper（`android/gradlew` 不存在），安卓单测无法在
/// CI/本地用 `flutter test` 触发。而安卓原生 UI 是**独立全屏宿主**，
/// Flutter 面板在其下方已卸载——这块面板是安卓 HDR/DV 排查的唯一入口。
///
/// 这里做的是**结构级检查**：文件存在、状态字段贯通、纯逻辑抽离、
/// 旧实现移除。语法级正确性由 `DebugPanelFormatTest.kt`（JVM）保证。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const statePath =
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerState.kt';
  const viewPath =
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'DebugPanelView.kt';
  const formatPath =
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'DebugPanelFormat.kt';
  const hostPath =
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerHost.kt';
  const screenPath =
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt';
  const testPath =
      'android/app/src/test/kotlin/com/himi/syncwatch/nativeplayer/'
      'DebugPanelFormatTest.kt';

  late String state;
  late String view;
  late String format;
  late String host;
  late String screen;

  setUpAll(() {
    // Kotlin 长行会折行（如 `videoParamsPixelFormat =\n json.optString(...)`），
    // 压掉多余空白后断言才稳定。
    state = read(statePath).replaceAll(RegExp(r'\s+'), ' ');
    view = read(viewPath);
    format = read(formatPath);
    host = read(hostPath);
    screen = read(screenPath);
  });

  group('1. 文件与职责划分', () {
    test('1.1 面板与纯逻辑文件存在', () {
      expect(File(viewPath).existsSync(), isTrue);
      expect(File(formatPath).existsSync(), isTrue);
      expect(File(testPath).existsSync(), isTrue);
    });

    test('1.2 纯判定逻辑抽到 DebugPanelFormat（JVM 可测）', () {
      // View 依赖 Android SDK，无法在 JVM 单测里构造；
      // 判定逻辑必须独立成 object 才能被 DebugPanelFormatTest 覆盖。
      expect(format, contains('internal object DebugPanelFormat'));
      expect(format, contains('fun backendSupportsDv'));
      expect(format, contains('fun dropSeverity'));
      expect(format, contains('fun dvToneMappingOk'));
      expect(format, contains('fun isHdrOutput'));
      expect(format, contains('fun dvProfileText'));
    });

    test('1.3 View 不重复实现判定逻辑', () {
      expect(view, isNot(contains('fun backendSupportsDv')));
      expect(view, isNot(contains('fun dropSeverity')));
      expect(view, contains('DebugPanelFormat.'));
    });
  });

  group('2. 状态字段贯通（漏字段 = 面板恒显示默认值）', () {
    test('2.1 数据类声明全部 HDR/DV 字段', () {
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
        expect(state.contains('val $f:'), isTrue, reason: '缺字段声明 $f');
        expect(state.contains('$f = json.'), isTrue, reason: 'fromJson 缺 $f');
      }
    });

    test('2.2 类型正确（double 字段不能用 optInt）', () {
      expect(state, contains('val videoParamsSigPeak: Double'));
      expect(state, contains('val estimatedVfFps: Double'));
      expect(state, contains('json.optDouble("videoParamsSigPeak"'));
      expect(state, contains('json.optDouble("estimatedVfFps"'));
      expect(state, contains('val doviProfile: Int'));
      expect(state, contains('json.optInt("doviProfile"'));
    });
  });

  group('3. 面板行为', () {
    test('3.1 半透明（0.72）+ 可拖动', () {
      expect(view, contains('Color.argb(184, 0, 0, 0)')); // 184/255 ≈ 0.72
      expect(view, contains('MotionEvent.ACTION_MOVE'));
      expect(view, contains('x += event.rawX - dragStartX'));
      expect(view, contains('y += event.rawY - dragStartY'));
    });

    test('3.2 五个分组齐全', () {
      expect(view, contains('"播放"'));
      expect(view, contains('"HDR 输入"'));
      expect(view, contains('"HDR 输出"'));
      expect(view, contains('"杜比视界"'));
      expect(view, contains('"渲染管线"'));
    });

    test('3.3 分组可折叠', () {
      expect(view, contains('private val collapsed = mutableSetOf<String>()'));
      expect(view, contains('collapsed.add(key)'));
      expect(view, contains('collapsed.remove(key)'));
    });

    test('3.4 分组键用常量而非标题反查', () {
      // 标题是展示文案，改名不该破坏折叠态
      expect(view, contains('const val KEY_PLAYBACK'));
      expect(view, contains('const val KEY_INPUT'));
      expect(view, contains('const val KEY_OUTPUT'));
      expect(view, contains('const val KEY_DV'));
      expect(view, isNot(contains('fun groupKey(')));
    });

    test('3.5 显隐由 showDebug + locked 驱动', () {
      // 锁定态必须隐藏：旧实现在锁定分支单独设 GONE，但每次状态推送
      // 都会再调 apply → 立刻重新显示，锁定态形同虚设。
      expect(view, contains('if (!state.showDebug || state.locked)'));
      expect(view, contains('visibility = GONE'));
      expect(view, contains('visibility = VISIBLE'));
      // 宿主侧不再单独设 GONE（单一真相）
      expect(screen, isNot(contains('debugPanel.visibility = GONE')));
    });

    test('3.5b 面板限高（分组全展开不会溢出屏幕）', () {
      // ScrollView WRAP_CONTENT 会撑到内容全高 → 小屏底部行看不到
      expect(view, contains('fun applyMaxHeight('));
      expect(view, contains('screenHeightPx * 0.78f'));
      expect(screen, contains('debugPanel.applyMaxHeight('));
    });

    test('3.6 接收 Surface 实际尺寸（安卓画质核验口径）', () {
      // 「画面变糊」的根因是 surface 被写成 1/3 尺寸，
      // 这个值只有宿主知道（Dart 侧拿不到）。
      expect(view, contains('surfaceWidthPx'));
      expect(view, contains('surfaceHeightPx'));
      expect(view, contains('lastSurfaceSize'));
      expect(view, contains('"Surface 尺寸"'));
      expect(screen, contains('debugPanel.apply(state, surfaceWidthPx = sw'));
    });
  });

  group('4. 宿主接线', () {
    test('4.1 面板挂在根 FrameLayout 且可拖动定位', () {
      expect(screen, contains('private val debugPanel = DebugPanelView(context)'));
      expect(screen, contains('addView(\n            debugPanel,'));
      expect(screen, contains('it.leftMargin = dp(16)'));
      expect(screen, contains('it.topMargin = dp(80)'));
    });

    test('4.2 关闭回调走 listener（不是未定义字段）', () {
      expect(screen, contains('fun onCloseDebugPanel()'));
      expect(screen, contains('listener?.onCloseDebugPanel()'));
      expect(screen, isNot(contains('hostCallback')));
    });

    test('4.3 Host 发送 toggleDebug 命令', () {
      expect(host, contains('override fun onCloseDebugPanel()'));
      expect(host, contains('"type" to "toggleDebug"'));
    });

    test('4.4 旧 diagText / buildDiag 代码已移除（注释可提及）', () {
      // 注释里说明「替代旧的 diagText」是正常的；要保证的是没有代码引用。
      expect(screen, isNot(contains('private val diagText')));
      expect(screen, isNot(contains('diagText.text')));
      expect(screen, isNot(contains('diagText.visibility')));
      expect(screen, isNot(contains('fun buildDiag(')));
      expect(screen, isNot(contains('buildDiag(state')));
    });
  });

  group('5. 与 Dart / Qt 端判定一致', () {
    test('5.1 后端关键词三端相同', () {
      const keywords = ['d3d11', 'vulkan', 'ohosvk'];
      for (final k in keywords) {
        expect(format, contains('contains("$k")'),
            reason: '安卓缺关键词 $k');
      }
      // Flutter 与 Qt 侧已由各自测试覆盖，这里只锁安卓侧。
    });

    test('5.2 丢帧阈值三端相同', () {
      expect(format, contains('> 100'));
      expect(format, contains('> 10'));
    });

    test('5.3 DV 映射要求 bt.2390', () {
      expect(format, contains('toneMapping == "bt.2390"'));
    });
  });
}

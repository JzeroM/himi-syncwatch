import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：鸿蒙原生调试面板（`DebugPanel.ets` + `DebugPanelFormat.ets`）。
///
/// ## 为什么用 Dart 测 ArkTS
///
/// 鸿蒙构建需要 DevEco 工具链（不在 `flutter test` 的覆盖范围内），
/// 而鸿蒙原生播放器 UI 是**独立全屏宿主**，Flutter 面板在其下方已卸载
/// ——这块面板是鸿蒙 HDR/DV 排查的唯一入口。
///
/// 这里做**结构级检查**：文件存在、状态字段贯通、判定逻辑抽离、
/// ArkTS 观察链正确（`@Prop` 不支持自定义类）、旧实现移除。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const base = 'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native';
  const hostPath = '$base/HimiMpvNativeHost.ets';
  const viewPath = '$base/HimiNativePlayerView.ets';
  const panelPath = '$base/DebugPanel.ets';
  const formatPath = '$base/DebugPanelFormat.ets';

  late String host;
  late String view;
  late String panel;
  late String format;

  setUpAll(() {
    // ArkTS 长行会折行，压掉多余空白后断言才稳定
    host = read(hostPath).replaceAll(RegExp(r'\s+'), ' ');
    view = read(viewPath);
    panel = read(panelPath);
    format = read(formatPath);
  });

  group('1. 文件与职责划分', () {
    test('1.1 面板与纯逻辑文件存在', () {
      expect(File(panelPath).existsSync(), isTrue);
      expect(File(formatPath).existsSync(), isTrue);
    });

    test('1.2 判定逻辑抽到 DebugPanelFormat', () {
      expect(format, contains('export function backendSupportsDv'));
      expect(format, contains('export function dropSeverity'));
      expect(format, contains('export function dvToneMappingOk'));
      expect(format, contains('export function isHdrOutput'));
      expect(format, contains('export function dvProfileText'));
      expect(format, contains('export class DebugSeverity'));
    });

    test('1.3 面板不重复实现判定逻辑', () {
      expect(panel, isNot(contains('export function backendSupportsDv')));
      expect(panel, isNot(contains('export function dropSeverity')));
      // 必须从 format 导入
      expect(panel, contains("from './DebugPanelFormat'"));
      expect(panel, contains('backendSupportsDv('));
    });
  });

  group('2. 状态字段贯通', () {
    test('2.1 状态类声明全部 HDR/DV 字段', () {
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
        expect(host.contains('$f:'), isTrue, reason: '缺字段声明 $f');
        expect(
          host.contains('this.$f = json'),
          isTrue,
          reason: 'update 缺 $f 解析',
        );
      }
    });

    test('2.2 数值字段用 jsonNum 而非 jsonStr', () {
      expect(host, contains('this.videoParamsSigPeak = jsonNum('));
      expect(host, contains('this.estimatedVfFps = jsonNum('));
      expect(host, contains('this.doviProfile = jsonNum('));
      expect(host, contains('this.dvContent = jsonBool('));
    });
  });

  group('3. ArkTS 观察链正确性', () {
    test('3.1 用 revision 触发刷新（@Prop 不支持自定义类）', () {
      // ArkTS 的 @Prop 只观察基础类型；传 NativePlayerUiState 不会重绘。
      expect(panel, contains('@Prop revision: number'));
      // 注释里会提到「不用 @Prop state: NativePlayerUiState」——只要求
      // 实际声明里没有它
      expect(panel, isNot(contains('\n  @Prop state:')));
      expect(panel, contains('private host: HimiMpvNativeHost'));
      expect(panel, contains('HimiMpvNativeHost.getInstance()'));
    });

    test('3.2 ForEach key 带 revision（状态变化才重建）', () {
      expect(panel, contains('-\${this.revision}'));
    });

    test('3.3 面板由宿主 revision 驱动', () {
      expect(view, contains('DebugPanel({'));
      expect(view, contains('revision: this.revision'));
    });
  });

  group('4. 面板行为', () {
    test('4.1 半透明（0.72）+ 可拖动', () {
      // 0xB8 = 184 ≈ 0.72 * 255
      expect(panel, contains('#B8000000'));
      expect(panel, contains('PanGesture()'));
      expect(panel, contains('this.offsetX += event.offsetX'));
      expect(panel, contains('this.offsetY += event.offsetY'));
    });

    test('4.1b 只用 position 定位（position+translate 叠加会跑位）', () {
      // 597 真机回归：两者都改位置，基准互相污染
      expect(panel, contains('.position({ x: 16 + this.offsetX'));
      expect(panel, isNot(contains('.translate({')));
    });

    test('4.2 五个分组齐全', () {
      expect(panel, contains("title: '播放'"));
      expect(panel, contains("title: 'HDR 输入'"));
      expect(panel, contains("title: 'HDR 输出'"));
      expect(panel, contains("title: '杜比视界'"));
      expect(panel, contains("title: '渲染管线'"));
    });

    test('4.3 HDR/DV 三个分组高亮', () {
      for (final title in ['HDR 输入', 'HDR 输出', '杜比视界']) {
        final idx = panel.indexOf("title: '$title'");
        expect(idx, greaterThan(0), reason: '缺分组 $title');
        // highlighted 声明在 title 之后（同一对象字面量内）
        final block = panel.substring(idx, idx + 200);
        expect(block, contains('highlighted: true'),
            reason: '$title 未高亮');
      }
    });

    test('4.4 分组可折叠', () {
      expect(panel, contains('@State private collapsed: string[] = []'));
      expect(panel, contains('this.collapsed.push(key)'));
      expect(panel, contains('this.collapsed.splice(idx, 1)'));
      // ArkTS 需整体替换数组才触发刷新
      expect(panel, contains('this.collapsed = this.collapsed.slice()'));
    });

    test('4.5 分组键用常量而非标题反查', () {
      expect(panel, contains("const KEY_PLAYBACK = 'playback'"));
      expect(panel, contains("const KEY_INPUT = 'input'"));
      expect(panel, contains("const KEY_OUTPUT = 'output'"));
      expect(panel, contains("const KEY_DV = 'dv'"));
      expect(panel, contains("const KEY_PIPELINE = 'pipeline'"));
    });

    test('4.6 显隐由 showDebug + locked 驱动', () {
      // 锁定态必须隐藏（与安卓同款问题：每次推送重建会覆盖单独设的隐藏）
      expect(panel, contains('if (!this.state().showDebug || this.state().locked)'));
    });

    test('4.7 画布尺寸取宿主实测值（鸿蒙画质核验口径）', () {
      expect(panel, contains('this.host.canvasWidth'));
      expect(panel, contains('this.host.canvasHeight'));
      expect(panel, contains("label: '画布'"));
    });
  });

  group('5. 宿主接线', () {
    test('5.1 关闭回调走 toggleDebug 命令', () {
      expect(host, contains('requestCloseDebugPanel(): void'));
      expect(host, contains("this.sendCommand('toggleDebug', null)"));
      expect(view, contains('requestCloseDebugPanel()'));
    });

    test('5.2 旧 diagLine 代码已移除（注释可提及）', () {
      expect(view, isNot(contains('private diagLine()')));
      expect(view, isNot(contains('this.diagLine()')));
    });
  });

  group('6. 四端判定一致性', () {
    test('6.1 后端关键词四端相同', () {
      // 【697 真机回归（安卓）】安卓 Vulkan 的上下文名是 `androidvk`，
      // 不含 `vulkan` 子串；四端统一用 `vk` 覆盖 androidvk / ohosvk。
      for (final k in ['d3d11', 'vulkan', 'vk']) {
        expect(format.contains("'$k'"), isTrue, reason: '鸿蒙缺关键词 $k');
      }
    });

    test('6.2 丢帧阈值四端相同', () {
      expect(format, contains('> 100'));
      expect(format, contains('> 10'));
    });

    test('6.3 DV 映射要求 bt.2390', () {
      expect(format, contains("toneMapping === 'bt.2390'"));
    });

    test('6.4 语义常量四端同名', () {
      expect(format, contains("static readonly NORMAL: string = 'normal'"));
      expect(format, contains("static readonly GOOD: string = 'good'"));
      expect(format, contains("static readonly WARN: string = 'warn'"));
      expect(format, contains("static readonly ERROR: string = 'error'"));
    });
  });
}

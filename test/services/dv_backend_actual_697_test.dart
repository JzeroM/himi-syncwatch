import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/render_backend.dart';

/// 697：调试面板「杜比视界 → 后端」误报的完整回归。
///
/// ## 真机现象（SM8550 / Adreno 740 / 安卓 14）
///
/// 面板显示：
///
///     杜比视界
///       Profile     P5（单层 IPT）
///       识别        已识别为 DV
///       后端        androidvk,android · 不支持 DV     ← 橙
///       P5 风险     后端不支持 DV，画面会偏色          ← 红
///     渲染管线
///       gpu-api     vulkan,opengl
///       gpu-context androidvk,android
///
/// 三个独立问题叠加成了这张图：
///
/// 1. **`androidvk` 不含 `vulkan` 子串** → 旧判定 `contains('vulkan')` 把
///    跑在 Vulkan 上的内容判成「不支持 DV」。
/// 2. **`gpu-api` / `gpu-context` 读回来是配置列表**（`OPT_SETTINGSLIST`），
///    不是实际选中值，用它判定等于拿「允许什么」冒充「用了什么」。
/// 3. **没有读 `current-gpu-context`**（mpv `vo->context_name`，唯一能
///    回答「实际走了哪个后端」的属性）。
///
/// 本文件锁住这三条：判定函数语义、实际值优先、四端接线。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String collector;
  late String adapter;
  late String state;
  late String ktFormat;
  late String ktView;
  late String ktState;
  late String etsFormat;
  late String etsPanel;
  late String etsHost;
  late String qtCpp;

  setUpAll(() {
    collector = read('lib/services/debug/debug_metrics_collector.dart');
    adapter = read('lib/services/player/mpv_player_adapter.dart');
    state = read('lib/services/player/native/native_player_state.dart');
    ktFormat = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/DebugPanelFormat.kt');
    ktView = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/DebugPanelView.kt');
    ktState = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/AndroidNativePlayerState.kt');
    etsFormat = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/DebugPanelFormat.ets');
    etsPanel = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/DebugPanel.ets');
    etsHost = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/HimiMpvNativeHost.ets');
    qtCpp = read('native/windows_qt_player/src/mpv_window.cpp');
  });

  group('1. 判定函数（共享实现）', () {
    test('1.1 androidvk 判为 Vulkan —— 真机误报的根因', () {
      expect(renderBackendOf('androidvk'), RenderBackend.vulkan);
      expect(backendSupportsDv('androidvk'), isTrue);
    });

    test('1.2 三个平台的真实上下文名', () {
      // 安卓 Vulkan / 安卓 OpenGL / 鸿蒙 Vulkan / Windows D3D11
      expect(renderBackendOf('androidvk'), RenderBackend.vulkan);
      expect(renderBackendOf('android'), RenderBackend.opengl);
      expect(renderBackendOf('ohosvk'), RenderBackend.vulkan);
      expect(renderBackendOf('d3d11'), RenderBackend.d3d11);
    });

    test('1.3 优先级列表只看第一项（第一项能起来的就是实际用的）', () {
      expect(renderBackendOf('androidvk,android'), RenderBackend.vulkan);
      expect(renderBackendOf('android,androidvk'), RenderBackend.opengl);
      expect(renderBackendOf('vulkan,opengl'), RenderBackend.vulkan);
      expect(renderBackendOf('opengl,vulkan'), RenderBackend.opengl);
    });

    test('1.4 空白/未知保守判不支持', () {
      for (final v in ['', '  ', ',', ',,', 'metal', 'software', 'null']) {
        expect(backendSupportsDv(v), isFalse, reason: '不应把 "$v" 判成支持');
      }
      expect(backendSupportsDv(null), isFalse);
    });

    test('1.5 大小写无关', () {
      expect(renderBackendOf('ANDROIDVK'), RenderBackend.vulkan);
      expect(renderBackendOf('D3D11'), RenderBackend.d3d11);
      expect(renderBackendOf('Android'), RenderBackend.opengl);
    });

    test('1.6 effectiveRenderContext：实际值优先，缺失才退回配置', () {
      expect(
        effectiveRenderContext(actual: 'androidvk', configured: 'vulkan,opengl'),
        'androidvk',
      );
      expect(
        effectiveRenderContext(actual: '', configured: 'vulkan,opengl'),
        'vulkan,opengl',
      );
      expect(
        effectiveRenderContext(actual: '  ', configured: 'd3d11'),
        'd3d11',
      );
    });

    test('1.7 后端标签可读', () {
      expect(renderBackendLabel(RenderBackend.vulkan), 'Vulkan');
      expect(renderBackendLabel(RenderBackend.d3d11), 'D3D11');
      expect(renderBackendLabel(RenderBackend.opengl), 'OpenGL');
    });
  });

  group('2. Dart 侧接线', () {
    test('2.1 适配器采集 current-gpu-context', () {
      expect(adapter, contains("'current-gpu-context'"),
          reason: '不读这个属性就无法判断实际后端');
    });

    test('2.2 会话状态携带 gpuContextActual', () {
      expect(adapter, contains('gpuContextActual:'));
      expect(state, contains('final String gpuContextActual;'));
      // JSON 下发（原生面板消费）
      expect(state, contains("'gpuContextActual': gpuContextActual"));
      expect(state, contains("json['gpuContextActual']"));
    });

    test('2.3 采集器也读实际值', () {
      expect(collector, contains("'current-gpu-context'"));
    });

    test('2.4 采集器不再自己写关键词（只有一份实现）', () {
      expect(collector, contains('backendSupportsDv('));
      // 旧实现的关键词组合必须消失——留着就是第二份可能跑偏的判定
      expect(
        collector,
        isNot(contains("ctx.contains('ohosvk')")),
        reason: '该判定已迁到 render_backend.dart',
      );
    });

    test('2.5 管线分组同时展示实际值与配置', () {
      expect(collector, contains('gpu-context 配置'));
    });

    test('2.6 实际后端变化时打一条日志（无面板截图也能判断）', () {
      // 之前的真机日志里只有配置列表，看日志判断不出实际后端。
      expect(adapter, contains('_logActualRenderBackendOnce'));
      expect(adapter, contains('实际渲染后端: gpu-context='));
      // 同一值只记一次（2s 刷新一次，不去重会刷屏）
      expect(adapter, contains('_loggedGpuContextActual'));
    });
  });

  group('3. 安卓原生面板（Kotlin）', () {
    test('3.1 格式化器认识 androidvk', () {
      expect(ktFormat, contains('fun renderBackendOf('));
      expect(ktFormat, contains("contains(\"vk\")"));
    });

    test('3.2 格式化器提供实际值优先入口', () {
      expect(ktFormat, contains('fun effectiveRenderContext('));
    });

    test('3.3 状态解析 gpuContextActual', () {
      expect(ktState, contains('val gpuContextActual: String'));
      expect(ktState, contains('json.optString("gpuContextActual"'));
    });

    test('3.4 DV 组用实际上下文判定（不再用配置列表）', () {
      final idx = ktView.indexOf('val supportsDv');
      expect(idx, greaterThan(0));
      final before = ktView.substring(
        idx > 400 ? idx - 400 : 0,
        idx,
      );
      expect(before, contains('effectiveRenderContext'));
      expect(before, contains('state.gpuContextActual'));
    });

    test('3.5 管线行优先显示实际值', () {
      expect(ktView, contains('fmt.effectiveRenderContext('));
    });
  });

  group('4. 鸿蒙面板（ArkTS）', () {
    test('4.1 格式化器认识 androidvk（与安卓同构）', () {
      expect(etsFormat, contains('export function renderBackendOf('));
      expect(etsFormat, contains("indexOf('vk')"));
      expect(etsFormat, contains('export function effectiveRenderContext('));
    });

    test('4.2 状态镜像 gpuContextActual', () {
      expect(etsHost, contains('gpuContextActual: string'));
      expect(etsHost, contains('jsonStr(obj.gpuContextActual'));
    });

    test('4.3 DV 组用实际上下文', () {
      expect(etsPanel, contains('effectiveRenderContext('));
      expect(etsPanel, contains('s.gpuContextActual'));
    });
  });

  group('5. Windows Qt 面板', () {
    test('5.1 管线行优先读 current-gpu-context', () {
      expect(qtCpp, contains('"current-gpu-context"'));
    });
  });

  group('6. mpv 属性语义（防止再凭印象写）', () {
    test('6.1 注释里写清「配置列表 ≠ 实际值」', () {
      // 这是本次误报的核心认知，必须留在代码里而不是只留在聊天记录
      expect(adapter, contains('current-gpu-context'));
      expect(collector, contains('配置列表'));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';
import 'package:himi_syncwatch/services/debug/render_backend.dart';

/// 697：调试指标采集器的**判定逻辑**（纯函数部分）。
///
/// ## 为什么拆出来测
///
/// 采集器本身依赖 `MpvPlayerAdapter`（需要真实 mpv），但它的价值在于
/// **判定**——「这个组合算正常还是异常」。判定错了，面板就会给出误导
/// 结论（比如把 P5 标成绿、把软解标成正常），比没有面板更糟。
///
/// 后端判定不再「复刻」——直接调用共享实现 [backendSupportsDv]，避免
/// 「测试里抄一份错的、实现里也是错的，于是测试通过」这种自欺欺人。
void main() {
  /// 复刻丢帧分级。
  Severity dropSeverity(int render, int decode) {
    if (render > 100 || decode > 100) return Severity.error;
    if (render > 10 || decode > 10) return Severity.warn;
    return Severity.good;
  }

  group('1. 后端 DV 能力判定', () {
    test('1.1 D3D11（Windows）支持', () {
      expect(backendSupportsDv('d3d11'), isTrue);
      expect(backendSupportsDv('D3D11'), isTrue);
    });

    test('1.2 Vulkan / ohosvk（鸿蒙）支持', () {
      expect(backendSupportsDv('vulkan'), isTrue);
      expect(backendSupportsDv('ohosvk'), isTrue);
      expect(backendSupportsDv('OHOSVK'), isTrue);
    });

    test('1.2b androidvk（安卓 Vulkan）支持 —— 697 真机回归', () {
      // 【关键】安卓 Vulkan 的上下文名是 `androidvk`，**不含** `vulkan`
      // 子串。旧判定 `contains('vulkan')` 把它误判成不支持 DV，导致
      // 真机截图报「后端 androidvk,android · 不支持 DV / 画面会偏色」。
      expect(backendSupportsDv('androidvk'), isTrue);
      expect(backendSupportsDv('ANDROIDVK'), isTrue);
      expect(renderBackendOf('androidvk'), RenderBackend.vulkan);
    });

    test('1.2c 优先级列表只看第一项', () {
      // 我们为了 Vulkan 失败能回落而下发 `androidvk,android`
      expect(backendSupportsDv('androidvk,android'), isTrue);
      expect(backendSupportsDv('vulkan,opengl'), isTrue);
      expect(backendSupportsDv('android,androidvk'), isFalse);
      expect(backendSupportsDv('opengl,vulkan'), isFalse);
    });

    test('1.2d 实际值优先于配置列表', () {
      expect(
        effectiveRenderContext(actual: 'androidvk', configured: 'androidvk,android'),
        'androidvk',
      );
      // 实际回落到了 GL → 即便配置里有 vulkan 也必须判「不支持」
      expect(
        effectiveRenderContext(actual: 'android', configured: 'androidvk,android'),
        'android',
      );
      expect(
        backendSupportsDv(
          effectiveRenderContext(actual: 'android', configured: 'androidvk,android'),
        ),
        isFalse,
      );
      // 实际值缺失（vo 还没起来）→ 退回配置列表
      expect(
        effectiveRenderContext(actual: '', configured: 'androidvk,android'),
        'androidvk,android',
      );
    });

    test('1.3 OpenGL ES（安卓）不支持', () {
      // 回落路径：Vulkan 初始化失败 → android（EGL/GLES），无可靠 compute
      expect(backendSupportsDv('android'), isFalse);
      expect(backendSupportsDv('opengl'), isFalse);
      expect(backendSupportsDv('opengles'), isFalse);
      expect(backendSupportsDv('gl'), isFalse);
      expect(backendSupportsDv(''), isFalse);
    });

    test('1.4 未知 context 保守判为不支持', () {
      // 宁可信其无：判错成「支持」会让人误以为 P5 没问题
      expect(backendSupportsDv('metal'), isFalse);
      expect(backendSupportsDv('software'), isFalse);
    });
  });

  group('2. 丢帧分级', () {
    test('2.1 少量丢帧正常', () {
      expect(dropSeverity(0, 0), Severity.good);
      expect(dropSeverity(5, 3), Severity.good);
      expect(dropSeverity(10, 10), Severity.good);
    });

    test('2.2 中等丢帧可疑', () {
      expect(dropSeverity(11, 0), Severity.warn);
      expect(dropSeverity(0, 11), Severity.warn);
      expect(dropSeverity(100, 100), Severity.warn);
    });

    test('2.3 大量丢帧异常', () {
      expect(dropSeverity(101, 0), Severity.error);
      expect(dropSeverity(0, 101), Severity.error);
    });
  });

  group('3. HDR 输入识别（video-params 三元组）', () {
    test('3.1 HDR10：bt.2020 + pq', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'sig-peak': 1000,
      }))!;
      expect(v.isHdr, isTrue);
      expect(v.isHlg, isFalse);
      expect(v.isDolbyVision, isFalse);
    });

    test('3.2 HLG：bt.2020 + hlg', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'primaries': 'bt.2020',
        'gamma': 'hlg',
      }))!;
      expect(v.isHdr, isTrue);
      expect(v.isHlg, isTrue);
    });

    test('3.3 SDR：bt.709 + bt.1886', () {
      final v = VideoColorInfo.tryParse(jsonEncode({
        'primaries': 'bt.709',
        'gamma': 'bt.1886',
      }))!;
      expect(v.isHdr, isFalse);
      expect(v.isHlg, isFalse);
    });

    test('3.4 DV P5 是单层 IPT（后端不支持必偏色）', () {
      // DV 在 current-tracks/video 下（mpv 源码实证，不在 video-params）
      final v = VideoColorInfo.fromProperties(const {
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'current-tracks/video/dolby-vision-profile': '5',
      })!;
      expect(v.isDolbyVision, isTrue);
      expect(v.doviProfile, 5);
      // 安卓 OpenGL 后端 → 必须报 P5 风险
      expect(backendSupportsDv('opengl'), isFalse);
    });

    test('3.5 DV P8 是兼容层（HDR10 基线 + RPU）', () {
      final v = VideoColorInfo.fromProperties(const {
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'current-tracks/video/dolby-vision-profile': '8',
        'current-tracks/video/dolby-vision-level': '6',
      })!;
      expect(v.isDolbyVision, isTrue);
      expect(v.doviProfile, 8);
      expect(v.doviLevel, 6);
    });
  });

  group('4. DV tone-mapping 正确性判定', () {
    // 与采集器/面板同一语义：非 DV 不约束，DV 必须 bt.2390
    bool dvMappingOk(bool isDv, String toneMapping) =>
        !isDv || toneMapping == 'bt.2390';

    test('4.1 DV + bt.2390 = 正确', () {
      // 697 修复：DV 必须感知映射，否则高光细节丢失
      expect(dvMappingOk(true, 'bt.2390'), isTrue);
    });

    test('4.2 DV + clip = 错误（会报红）', () {
      expect(dvMappingOk(true, 'clip'), isFalse);
    });

    test('4.3 非 DV 用 clip 是正常的（不该报错）', () {
      expect(dvMappingOk(false, 'clip'), isTrue);
    });
  });

  group('5. 输出 HDR 判定（target-trc）', () {
    test('5.1 pq / hlg 算 HDR 输出', () {
      bool isHdrOut(String trc) => trc == 'pq' || trc == 'hlg';
      expect(isHdrOut('pq'), isTrue);
      expect(isHdrOut('hlg'), isTrue);
    });

    test('5.2 auto / bt.1886 算 SDR 输出', () {
      bool isHdrOut(String trc) => trc == 'pq' || trc == 'hlg';
      expect(isHdrOut('auto'), isFalse);
      expect(isHdrOut('bt.1886'), isFalse);
    });
  });

  group('6. 三端判定逻辑必须一致', () {
    test('6.1 判定只有一份实现（共享 render_backend.dart）', () {
      // 采集器不再自己写关键词，必须委托给共享实现——否则复制出第二份
      // 判定就会再次出现「一处修好、另一处还是旧 bug」。
      final collector = File(
        'lib/services/debug/debug_metrics_collector.dart',
      ).readAsStringSync();
      expect(collector, contains('backendSupportsDv('));
      expect(collector, contains("import 'package:himi_syncwatch/services/"
          "debug/render_backend.dart'"));
      // Qt 面板输出实际上下文（current-gpu-context 优先）
      final qtCpp =
          File('native/windows_qt_player/src/mpv_window.cpp').readAsStringSync();
      expect(qtCpp, contains('current-gpu-context'));
    });

    test('6.2 后端标签给出能力结论而非光秃秃的 context 名', () {
      final collector = File(
        'lib/services/debug/debug_metrics_collector.dart',
      ).readAsStringSync();
      expect(collector, contains('支持 DV'));
      expect(collector, contains('不支持 DV'));
    });
  });
}

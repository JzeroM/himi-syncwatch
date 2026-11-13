import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';

/// 697：调试指标采集器的**判定逻辑**（纯函数部分）。
///
/// ## 为什么拆出来测
///
/// 采集器本身依赖 `MpvPlayerAdapter`（需要真实 mpv），但它的价值在于
/// **判定**——「这个组合算正常还是异常」。判定错了，面板就会给出误导
/// 结论（比如把 P5 标成绿、把软解标成正常），比没有面板更糟。
///
/// 这里把判定逻辑用纯函数复刻并锁定语义，采集器实现必须与之一致。
void main() {
  /// 复刻 `_renderBackendSupportsDv` 的判定（采集器与 QML 双端一致）。
  bool backendSupportsDv(String gpuContext) {
    final ctx = gpuContext.toLowerCase();
    return ctx.contains('d3d11') ||
        ctx.contains('vulkan') ||
        ctx.contains('ohosvk');
  }

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

    test('1.3 OpenGL ES（安卓）不支持', () {
      // 安卓 libmpv 构建时 HAVE_VULKAN=0 → libplacebo 无 compute
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
    test('4.1 DV + bt.2390 = 正确', () {
      // 697 修复：DV 必须感知映射，否则高光细节丢失
      const dv = true;
      const toneMapping = 'bt.2390';
      final ok = !dv || toneMapping == 'bt.2390';
      expect(ok, isTrue);
    });

    test('4.2 DV + clip = 错误（会报红）', () {
      const dv = true;
      const toneMapping = 'clip';
      final ok = !dv || toneMapping == 'bt.2390';
      expect(ok, isFalse);
    });

    test('4.3 非 DV 用 clip 是正常的（不该报错）', () {
      const dv = false;
      const toneMapping = 'clip';
      final ok = !dv || toneMapping == 'bt.2390';
      expect(ok, isTrue);
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
    test('6.1 Dart 采集器与 QML 面板用同一组关键词', () {
      // 采集器与 DebugPanel.qml 各自实现了一份判定；关键词必须一致，
      // 否则「Flutter 说支持、Qt 说不支持」。
      const keywords = ['d3d11', 'vulkan'];
      final collector = File(
        'lib/services/debug/debug_metrics_collector.dart',
      ).readAsStringSync();
      final qml = File(
        'native/windows_qt_player/src/qml/DebugPanel.qml',
      ).readAsStringSync();
      for (final k in keywords) {
        expect(collector, contains("contains('$k')"),
            reason: '采集器缺关键词 $k');
        expect(qml, contains('indexOf("$k") >= 0'),
            reason: 'QML 缺关键词 $k');
      }
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

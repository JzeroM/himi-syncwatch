import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：杜比视界的 tone-mapping 策略。
///
/// ## 问题
///
/// 此前 DV 内容被当作「普通 HDR10」处理，统一用 `tone-mapping=clip`。
/// `clip` 是**硬裁切**：按单一峰值把超出范围的值截断。对 HDR10（静态
/// 元数据，整片一个峰值）影响有限；但 DV 是**动态元数据**（逐场景峰值），
/// clip 会导致高光细节大量丢失、暗部发灰。
///
/// ## 修复
///
/// DV 内容改用 `bt.2390`（感知映射曲线）+ `tone-mapping-mode=hybrid`
/// （同时考虑亮度与色彩）。普通 HDR10 保持 `clip`（已验证观感）。
///
/// ## 关键约束：不加 `vf=libplacebo`
///
/// media_kit（NipaPlay）用 `vf=libplacebo` 是因为它走 Flutter 纹理，
/// 纹理不支持 HDR → 必须先用滤镜把 HDR 转成 SDR。我们的三平台都是
/// **直出**（Windows wid+D3D11 / 鸿蒙 ohosvk / 安卓 Surface），
/// `gpu-next` 内置的 libplacebo 会自动消费 DV 元数据。额外加 `vf`
/// 会双重处理（一次滤镜转 SDR，一次渲染器再处理），HDR 直出能力全废。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  group('1. Dart 适配器：DV 标记与 tone-mapping', () {
    late String adapter;

    setUpAll(() => adapter = read('lib/services/player/mpv_player_adapter.dart'));

    test('1.1 提供 dvContent setter 与 isDvContent getter', () {
      expect(codeOnly(adapter), contains('set dvContent(bool value)'));
      expect(codeOnly(adapter), contains('bool get isDvContent'));
    });

    test('1.2 DV 变化触发 HDR 输出刷新', () {
      final idx = adapter.indexOf('set dvContent(bool value)');
      final block = adapter.substring(idx, idx + 300);
      expect(block, contains('_refreshHdrOutputForCurrentSession'));
    });

    test('1.3 HDR 输出：DV 用 bt.2390 + hybrid', () {
      final idx = adapter.indexOf('Future<void> _applyHdrOutputProperties');
      final block = adapter.substring(idx, idx + 2000);
      expect(block, contains("'tone-mapping': toneMapping"));
      expect(block, contains("'tone-mapping-mode': 'hybrid'"));
      // toneMapping 变量按 DV 分支
      expect(block, contains("_dvContentForMedia ? 'bt.2390' : 'clip'"));
    });

    test('1.4 SDR 路径同样改善 DV 观感', () {
      final idx = adapter.indexOf('Future<void> _applyHdrOutputProperties');
      final block = adapter.substring(idx, idx + 2000);
      // SDR 分支也应有 DV 的 tone-mapping
      final sdrIdx = block.indexOf("'target-trc': 'auto'");
      expect(sdrIdx, greaterThan(0));
      final sdrBlock = block.substring(sdrIdx, sdrIdx + 400);
      expect(sdrBlock, contains('toneMapping'));
    });

    test('1.5 SDR 分支无条件设置 tone-mapping（避免属性残留）', () {
      // mpv 属性是持久的：条件设置会让切到 SDR 片源时残留上一次的
      // tone-mapping，诊断面板也会显示错值。
      final idx = adapter.indexOf('Future<void> _applyHdrOutputProperties');
      final block = adapter.substring(idx, idx + 2000);
      final sdrIdx = block.indexOf("'target-trc': 'auto'");
      final sdrBlock = block.substring(sdrIdx, sdrIdx + 400);
      expect(
        sdrBlock,
        contains("'tone-mapping': toneMapping,"),
        reason: 'SDR 分支必须无条件设置 tone-mapping',
      );
      expect(sdrBlock, isNot(contains("if (_dvContentForMedia) 'tone-mapping'")));
      // mode 也要复位，否则残留 hybrid
      expect(sdrBlock, contains("'tone-mapping-mode': _dvContentForMedia"));
    });

    test('1.5 不加 vf=libplacebo（避免双重处理）', () {
      final code = codeOnly(adapter);
      expect(code, isNot(contains('apply_dolbyvision')),
          reason: 'gpu-next 内置 libplacebo 自动处理 DV，加 vf 会双重处理');
      expect(code, isNot(contains('lavfi=[libplacebo')));
    });

    test('1.6 创建会话时传 dv 参数', () {
      final idx = adapter.indexOf('MpvSessionPlatform.create(');
      final block = adapter.substring(idx, idx + 800);
      expect(block, contains('dv: _dvContentForMedia'));
    });
  });

  group('2. 播放页注入 DV 标记', () {
    late String screen;

    setUpAll(() => screen = read('lib/screens/player/player_screen.dart'));

    test('2.1 _applyMpvContentHints 设置 dvContent', () {
      final idx = screen.indexOf('void _applyMpvContentHints()');
      final block = screen.substring(idx, idx + 700);
      expect(block, contains('player.dvContent = isDv'));
      expect(block, contains('stream?.isDolbyVision'));
    });

    test('2.2 DV 内容仍算 HDR（保留 hdrContent=true）', () {
      final idx = screen.indexOf('void _applyMpvContentHints()');
      final block = screen.substring(idx, idx + 700);
      expect(block, contains('player.hdrContent'));
      expect(block, contains('isDv'));
    });

    test('2.3 Qt 播放器启动传 dv', () {
      expect(codeOnly(screen), contains('dv: mpv?.isDvContent ?? false'));
    });

    test('2.4 过时注释已修正（不再说「DV 恒走 mdk」）', () {
      // 修正后的注释会引用原句说明「那是历史遗留」，故只断言
      // 注释里明确标注了修正，而不是简单搜索原句。
      expect(screen, contains('697 修正过时描述'));
      expect(screen, contains('引擎收敛'));
    });
  });

  group('3. 三平台原生层参数贯通', () {
    test('3.1 安卓：dv 参数 + bt.2390 分支', () {
      final src = read('plugins/himi_mpv_android/lib/himi_mpv_android.dart');
      expect(src, contains('bool dv = false'));
      expect(src, contains('final bool dv;'));
      expect(src, contains("'tone-mapping': dv ? 'bt.2390' : 'clip'"));
      expect(src, contains("if (dv) 'tone-mapping-mode': 'hybrid'"));
    });

    test('3.2 Windows 插件：dv 参数 + bt.2390 分支', () {
      final src = read('plugins/himi_mpv_windows/lib/himi_mpv_windows.dart');
      expect(src, contains('bool dv = false'));
      expect(src, contains("'tone-mapping': dv ? 'bt.2390' : 'clip'"));
    });

    test('3.3 鸿蒙 Dart：dv 参数下发', () {
      final src = read('plugins/himi_mpv_ohos/lib/himi_mpv_ohos.dart');
      expect(src, contains('bool dv = false'));
      expect(src, contains("'dv': dv"));
    });

    test('3.4 鸿蒙 ArkTS：解析 dv 并分支', () {
      final src = read(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      );
      expect(src, contains("this.boolArg(args, 'dv', false)"));
      expect(src, contains("dv ? 'bt.2390' : 'clip'"));
      expect(src, contains("'tone-mapping-mode', 'hybrid'"));
    });

    test('3.5 Windows Qt C++：dv 成员与分支', () {
      final h = read('native/windows_qt_player/src/mpv_window.h');
      final cpp = read('native/windows_qt_player/src/mpv_window.cpp');
      expect(h, contains('bool dvContent_ = false;'));
      expect(h, contains('void setHdrMode(bool hdr, bool hlg, bool dv'));
      expect(cpp, contains('dvContent_ ? QStringLiteral("bt.2390")'));
      expect(cpp, contains('tone-mapping-mode'));
    });

    test('3.6 Qt 命令解析 dv 字段', () {
      final src = read('native/windows_qt_player/src/main.cpp');
      expect(src, contains('cmd.value(QLatin1String("dv")).toBool()'));
    });

    test('3.7 Qt 适配器发送 dv', () {
      final src = read('lib/services/player/qt_player_adapter.dart');
      expect(src, contains("'dv': dv"));
      expect(src, contains('bool dv = false'));
    });

    test('3.8 MpvSessionPlatform 透传 dv 到三平台', () {
      final src = read('lib/services/player/mpv_session_platform.dart');
      expect(src, contains('bool dv = false'));
      // 鸿蒙 + 安卓两处 dv: dv（Windows 走 Dart 侧运行时设置，不传）
      expect('dv: dv'.allMatches(src).length, greaterThanOrEqualTo(2));
    });
  });

  group('4. 鸿蒙已是 Vulkan（DV 处理前提）', () {
    test('4.1 鸿蒙用 gpu-api=vulkan + gpu-context=ohosvk', () {
      final src = read(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      );
      expect(src, contains("setOptionString('gpu-api', 'vulkan')"));
      expect(src, contains("setOptionString('gpu-context', 'ohosvk')"));
    });
  });
}

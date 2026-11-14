import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';

/// 697：mpv 属性字段名的**硬校验**。
///
/// ## 为什么需要这组测试
///
/// 697 第一次交付时，面板在鸿蒙上把 P5 显示成「非 DV 内容」。根因不是
/// UI 写错，而是我**凭空假设**了 mpv 的字段名：
///
/// ```dart
/// // 实际不存在这个字段（mpv 的 video-params 里没有它）
/// doviProfile: i('dovi-profile')
/// ```
///
/// 更糟的是当时的测试「通过」了——因为它断言的是我自己的错误假设：
///
/// ```dart
/// VideoColorInfo.tryParse(jsonEncode({'dovi-profile': 5}))  // 当然解析出 5
/// ```
///
/// 这类 bug 无法靠「解析自己的假数据」发现。唯一可靠的办法是把
/// **mpv 真实暴露的字段列表**固化进测试，字段名对不上就失败。
///
/// ## 数据来源
///
/// mpv 源码 `player/command.c` 的 `property_imgparams()`（video-params
/// 的字段表）与 `mpv_property_current_tracks`（current-tracks 的字段表）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// mpv `video-params` 实际暴露的字段（照 `property_imgparams` 抄录）。
  ///
  /// 【维护约定】升级 mpv 后若字段有变，改这张表**之前**先去源码核实。
  const videoParamsFields = <String>{
    'pixelformat',
    'hw-pixelformat',
    'average-bpp',
    'w',
    'h',
    'dw',
    'dh',
    'crop-x',
    'crop-y',
    'crop-w',
    'crop-h',
    'aspect',
    'aspect-name',
    'par',
    'sar',
    'sar-name',
    'colormatrix',
    'colorlevels',
    'primaries',
    'gamma',
    'sig-peak',
    'light',
    'chroma-location',
    'stereo-in',
    'rotate',
    'alpha',
    'min-luma',
    'max-luma',
    'max-cll',
    'max-fall',
    'scene-max-r',
    'scene-max-g',
    'scene-max-b',
    'scene-avg',
    'max-pq-y',
    'avg-pq-y',
    'prim-red-x',
    'prim-red-y',
    'prim-green-x',
    'prim-green-y',
    'prim-blue-x',
    'prim-blue-y',
    'prim-white-x',
    'prim-white-y',
  };

  /// `current-tracks/<type>` 实际暴露的字段（DV 在这里，不在 video-params）。
  const currentTrackFields = <String>{
    'dolby-vision-profile',
    'dolby-vision-level',
    'codec',
    'codec-desc',
    'codec-profile',
    'demux-w',
    'demux-h',
    'demux-fps',
    'demux-bitrate',
  };

  group('1. 属性清单里的字段必须真实存在', () {
    test('1.1 video-params 子属性全部在 mpv 字段表内', () {
      final names = VideoColorInfo.propertyNames
          .where((n) => n.startsWith('video-params/'));
      expect(names, isNotEmpty, reason: '清单为空说明常量被改坏了');
      for (final n in names) {
        final field = n.substring('video-params/'.length);
        expect(
          videoParamsFields.contains(field),
          isTrue,
          reason: 'mpv 的 video-params 没有字段 "$field"'
              '（697 曾凭空写 dovi-profile 导致鸿蒙 P5 误判）',
        );
      }
    });

    test('1.2 current-tracks/video 子属性全部在字段表内', () {
      final names = VideoColorInfo.propertyNames
          .where((n) => n.startsWith('current-tracks/video/'));
      for (final n in names) {
        final field = n.substring('current-tracks/video/'.length);
        expect(
          currentTrackFields.contains(field),
          isTrue,
          reason: 'mpv 的 current-tracks/video 没有字段 "$field"',
        );
      }
    });

    test('1.3 DV 字段必须挂在 current-tracks/video 下', () {
      // 这是 697 的核心错误：DV 不在 video-params 里
      expect(
        VideoColorInfo.propertyNames,
        contains('current-tracks/video/dolby-vision-profile'),
      );
      expect(
        VideoColorInfo.propertyNames,
        contains('current-tracks/video/dolby-vision-level'),
      );
      // 反向断言：绝不能写在 video-params 下
      expect(
        VideoColorInfo.propertyNames.where((n) => n.contains('dovi-profile')),
        isEmpty,
        reason: 'video-params 没有 dovi-profile 字段',
      );
    });

    test('1.4 不得出现 video-params/dovi-* 这类不存在的路径', () {
      for (final n in VideoColorInfo.propertyNames) {
        expect(
          n.startsWith('video-params/dovi'),
          isFalse,
          reason: '"$n" 是错误路径（DV 在 current-tracks/video 下）',
        );
      }
    });
  });

  group('2. 标量路径（鸿蒙只支持 number/bool/string）', () {
    test('2.1 清单里不能有整块 NODE 属性', () {
      // 鸿蒙的 MpvLib 只暴露 getProperty/getPropertyBool/getPropertyString，
      // 整块 video-params（NODE）读出来是空串。
      expect(VideoColorInfo.propertyNames, isNot(contains('video-params')));
      expect(VideoColorInfo.propertyNames, isNot(contains('track-list')));
      expect(VideoColorInfo.propertyNames, isNot(contains('audio-params')));
    });

    test('2.2 每条都是子属性路径（最多三层）', () {
      // 两种合法形态：
      //   video-params/primaries                     （2 层）
      //   current-tracks/video/dolby-vision-profile  （3 层）
      for (final n in VideoColorInfo.propertyNames) {
        expect(n.contains('/'), isTrue, reason: '"$n" 不是子属性路径');
        expect(
          n.split('/').length,
          lessThanOrEqualTo(3),
          reason: '"$n" 层级过深',
        );
      }
    });
  });

  group('3. sig-peak 单位（mpv 是归一化倍数，不是 nits）', () {
    test('3.1 sigPeakNits 做 ×100 换算', () {
      // mpv 源码：{"sig-peak", SUB_PROP_FLOAT(max_luma / MP_REF_WHITE)}
      // MP_REF_WHITE = 100 → 5 表示 500 nits
      const info = VideoColorInfo(sigPeak: 5);
      expect(info.sigPeakNits, 500);
    });

    test('3.2 从属性构建时保留原始倍数', () {
      final info = VideoColorInfo.fromProperties(const {
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'video-params/sig-peak': '5',
      });
      expect(info, isNotNull);
      expect(info!.sigPeak, 5); // 原始倍数
      expect(info.sigPeakNits, 500); // 显示用
    });

    test('3.3 面板显示的是 nits 而非倍数', () {
      // 三端面板都必须 ×100（否则显示「5 nits」，差 100 倍）
      final collector =
          read('lib/services/debug/debug_metrics_collector.dart');
      expect(collector, contains('v.sigPeakNits'));

      final ohos =
          read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
              'DebugPanel.ets');
      expect(ohos, contains('s.videoParamsSigPeak * 100'));

      // Windows 与其他三端不同：mpv 在独立进程，数据由 Qt 侧自己读，
      // 所以 ×100 换算在 C++ 里（`MpvWindow::debugText`）。
      final qtCpp = read('native/windows_qt_player/src/mpv_window.cpp');
      expect(qtCpp, contains('sigPeak * 100.0'));

      final android = read(
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
          'DebugPanelView.kt');
      expect(android, contains('state.videoParamsSigPeak * 100'));
    });
  });

  group('4. fromProperties 解析', () {
    test('4.1 完整字段解析', () {
      final info = VideoColorInfo.fromProperties(const {
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'video-params/sig-peak': '10',
        'video-params/pixelformat': 'yuv420p10',
        'video-params/w': '3840',
        'video-params/h': '2160',
        'current-tracks/video/dolby-vision-profile': '5',
        'current-tracks/video/dolby-vision-level': '6',
      });
      expect(info, isNotNull);
      expect(info!.primaries, 'bt.2020');
      expect(info.gamma, 'pq');
      expect(info.sigPeak, 10);
      expect(info.sigPeakNits, 1000);
      expect(info.pixelFormat, 'yuv420p10');
      expect(info.width, 3840);
      expect(info.height, 2160);
      expect(info.doviProfile, 5);
      expect(info.doviLevel, 6);
      expect(info.isDolbyVision, isTrue);
      expect(info.bitDepth, 10);
    });

    test('4.2 空 Map 返回 null（未起播）', () {
      expect(VideoColorInfo.fromProperties(const {}), isNull);
    });

    test('4.3 只有无关字段时返回 null', () {
      expect(
        VideoColorInfo.fromProperties(const {'target-prim': 'bt.2020'}),
        isNull,
      );
    });

    test('4.4 缺 DV 字段时 profile 为 0（不抛）', () {
      final info = VideoColorInfo.fromProperties(const {
        'video-params/gamma': 'pq',
      });
      expect(info, isNotNull);
      expect(info!.doviProfile, 0);
      expect(info.isDolbyVision, isFalse);
    });
  });

  group('5. Emby 兜底链路', () {
    test('5.1 适配器提供 embyDoviProfile', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      expect(adapter, contains('int get embyDoviProfile'));
      expect(adapter, contains('set embyDoviProfile(int value)'));
    });

    test('5.2 播放页从 Emby 的 ExtendedVideoSubType 解析 Profile', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(screen, contains('_embyDoviProfileFrom'));
      expect(screen, contains("sub.contains('Profile50')"));
      expect(screen, contains('return 5;'));
      expect(screen, contains("sub.contains('Profile76')"));
      expect(screen, contains('return 7;'));
      expect(screen, contains("sub.contains('Profile81')"));
      expect(screen, contains("sub.contains('Profile84')"));
    });

    test('5.3 mpv 读不到时用 Emby 兜底', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      final idx = adapter.indexOf('doviProfile: (_colorInfo?.doviProfile');
      expect(idx, greaterThan(0));
      final block = adapter.substring(idx, idx + 200);
      expect(block, contains('_embyDoviProfile'));
    });

    test('5.4 四端面板都用 dvContent 兜底判 DV', () {
      final collector =
          read('lib/services/debug/debug_metrics_collector.dart');
      expect(collector, contains('_adapter.isDvContent'));

      final ohos =
          read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
              'DebugPanel.ets');
      expect(ohos, contains('s.doviProfile > 0 || s.dvContent'));

      // Windows：判定在 C++ 侧（Qt 自己读 mpv）
      final qtCpp = read('native/windows_qt_player/src/mpv_window.cpp');
      expect(qtCpp, contains('dvProfile > 0 || dvContent_'));

      final android = read(
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
          'DebugPanelView.kt');
      expect(android, contains('state.doviProfile > 0 || state.dvContent'));
    });
  });

  group('6. 安卓 getVideoParams 不再是伪造的', () {
    test('6.1 读真实子属性而非只拼 w/h', () {
      final android = read('plugins/himi_mpv_android/lib/himi_mpv_android.dart');
      expect(android, contains("'video-params/primaries'"));
      expect(android, contains("'video-params/gamma'"));
      expect(android, contains("'video-params/sig-peak'"));
      // 旧实现只有 {'w','h'}，没有任何色彩字段
      expect(
        android.contains("jsonEncode(<String, dynamic>{'w': w, 'h': h})"),
        isFalse,
        reason: '旧实现是伪造的，必须改为读真实属性',
      );
    });
  });

  group('7. 数据新鲜度（_debugProps 不能只在面板开启时刷新）', () {
    test('7.1 有独立的低频刷新定时器', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      expect(adapter, contains('_startNativeDebugRefresh'));
      expect(adapter, contains('_stopNativeDebugRefresh'));
      expect(adapter, contains('Duration(seconds: 2)'));
    });

    test('7.2 起播时启动、dispose 时停止', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      // 启动点与 _startPolling 相邻（同一处起播入口）
      final startIdx = adapter.indexOf('_startPolling();\n    // 697：原生 UI');
      expect(startIdx, greaterThan(0), reason: '起播时未启动调试属性刷新');
      expect(adapter, contains('_stopNativeDebugRefresh();'));
    });

    test('7.3 target-prim / tone-mapping 有状态兜底', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      expect(adapter, contains("_debugProps['target-prim'] ?? _targetPrim"));
      expect(
        adapter,
        contains("_debugProps['tone-mapping'] ?? _targetToneMapping"),
      );
    });
  });
}

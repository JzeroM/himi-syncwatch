import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_theme.dart';

/// 跨语言主题常量一致性：Dart `NativePlayerTheme` 是唯一真相源，
/// Android（Kotlin `NPTheme`）与鸿蒙（ArkTS `NativePlayerPanel.ets`）
/// 必须逐项同值。改动任一端必须同步三端，否则测试失败。
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerUi.kt',
  ).readAsStringSync();

  final arkts = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerPanel.ets',
  ).readAsStringSync();

  /// 从 Kotlin 源码里按名字取 `const val NAME = <值>` 的十六进制字面量。
  int kotlinHex(String name) {
    final m = RegExp('const val $name = (0x[0-9A-Fa-f]+)').firstMatch(kotlin);
    expect(m, isNotNull, reason: 'Kotlin NPTheme 缺少常量 $name');
    return int.parse(m!.group(1)!.substring(2), radix: 16);
  }

  /// 从 Kotlin 源码里按名字取 `const val NAME = <数值>` 的整数。
  int kotlinInt(String name) {
    final m = RegExp('const val $name = ([0-9.]+)').firstMatch(kotlin);
    expect(m, isNotNull, reason: 'Kotlin NPTheme 缺少常量 $name');
    return double.parse(m!.group(1)!).round();
  }

  group('Dart ↔ Android（Kotlin NPTheme）', () {
    test('强调色与灰阶', () {
      expect(kotlinHex('ACCENT'), NativePlayerTheme.accent.toARGB32());
      expect(kotlinHex('ACCENT_SOFT'), NativePlayerTheme.accentSoft.toARGB32());
      expect(kotlinHex('WHITE'), NativePlayerTheme.white.toARGB32());
      expect(kotlinHex('WHITE_70'), NativePlayerTheme.white70.toARGB32());
      expect(kotlinHex('WHITE_54'), NativePlayerTheme.white54.toARGB32());
      expect(kotlinHex('WHITE_38'), NativePlayerTheme.white38.toARGB32());
      expect(kotlinHex('WHITE_24'), NativePlayerTheme.white24.toARGB32());
      expect(kotlinHex('WHITE_12'), NativePlayerTheme.white12.toARGB32());
      expect(kotlinHex('ACCENT_30'), NativePlayerTheme.accent30.toARGB32());
    });

    test('玻璃/浮层色', () {
      expect(kotlinHex('PANEL_TINT'), NativePlayerTheme.panelTint.toARGB32());
      expect(kotlinHex('FALLBACK_TINT'), NativePlayerTheme.fallbackTint.toARGB32());
      expect(kotlinHex('RIM'), NativePlayerTheme.rim.toARGB32());
      expect(kotlinHex('DECODE_PANEL'), NativePlayerTheme.decodePanel.toARGB32());
      expect(
        kotlinHex('DECODE_CURRENT_TEXT'),
        NativePlayerTheme.decodeCurrentText.toARGB32(),
      );
      expect(kotlinHex('FOCUS_RING'), NativePlayerTheme.focusRing.toARGB32());
      expect(kotlinHex('SHADOW'), NativePlayerTheme.shadow.toARGB32());
    });

    test('圆角', () {
      expect(kotlinInt('RADIUS_PANEL'), NativePlayerTheme.radiusPanel.round());
      expect(kotlinInt('RADIUS_CHIP'), NativePlayerTheme.radiusChip.round());
      expect(kotlinInt('RADIUS_CARD'), NativePlayerTheme.radiusCard.round());
      expect(kotlinInt('RADIUS_DECODE'), NativePlayerTheme.radiusDecode.round());
      expect(kotlinInt('RADIUS_BADGE'), NativePlayerTheme.radiusBadge.round());
    });

    test('顶栏', () {
      expect(kotlinInt('TOP_BAR_HEIGHT'), NativePlayerTheme.topBarHeight.round());
      expect(kotlinInt('TOP_ICON_SIZE'), NativePlayerTheme.topIconSize.round());
      expect(
        kotlinInt('TOP_CHIP_ICON_SIZE'),
        NativePlayerTheme.topChipIconSize.round(),
      );
      expect(kotlinInt('TITLE_SIZE'), NativePlayerTheme.titleSize.round());
      expect(
        kotlinInt('TITLE_MIN_WIDTH'),
        NativePlayerTheme.titleMinWidth.round(),
      );
      expect(kotlinInt('CAPTION_SIZE'), NativePlayerTheme.captionSize.round());
      expect(kotlinInt('CHIP_PAD_H'), NativePlayerTheme.chipPadH.round());
      expect(kotlinInt('CHIP_PAD_V'), NativePlayerTheme.chipPadV.round());
      expect(kotlinInt('CLOCK_WIDTH'), NativePlayerTheme.clockWidth.round());
      expect(kotlinInt('CLOCK_HEIGHT'), NativePlayerTheme.clockHeight.round());
      expect(kotlinInt('CLOCK_RIGHT'), NativePlayerTheme.clockRight.round());
    });

    test('底栏', () {
      expect(kotlinInt('LOGO_WIDTH'), NativePlayerTheme.logoWidth.round());
      expect(kotlinInt('LOGO_HEIGHT'), NativePlayerTheme.logoHeight.round());
      // 顶/底栏渐变实端 alpha：顶栏 0xCC(0.8) / 底栏 0xD9(0.85)，
      // 与 Flutter `_buildTopBar` / `_buildControls` 同值。
      expect(
        kotlinHex('BAR_GRADIENT_SOLID'),
        NativePlayerTheme.barGradientSolid.toARGB32(),
      );
      expect(
        kotlinHex('BAR_BOTTOM_SOLID'),
        NativePlayerTheme.barBottomSolid.toARGB32(),
      );
      expect(kotlinInt('BAR_PAD_H'), NativePlayerTheme.barPadH.round());
      expect(kotlinInt('BAR_PAD_TOP'), NativePlayerTheme.barPadTop.round());
      expect(
        kotlinInt('BAR_PAD_BOTTOM'),
        NativePlayerTheme.barPadBottom.round(),
      );
      expect(kotlinInt('TIME_CELL'), NativePlayerTheme.timeCellWidth.round());
      expect(
        kotlinInt('TIME_CELL_WIDE'),
        NativePlayerTheme.timeCellWidthWide.round(),
      );
      expect(kotlinInt('SEEK_TRACK'), NativePlayerTheme.seekTrackHeight.round());
      expect(kotlinInt('SEEK_THUMB'), NativePlayerTheme.seekThumbRadius.round());
      expect(
        kotlinInt('TRANSPORT_SIDE'),
        NativePlayerTheme.transportSideSize.round(),
      );
      expect(
        kotlinInt('TRANSPORT_PLAY'),
        NativePlayerTheme.transportPlaySize.round(),
      );
      expect(kotlinInt('TRANSPORT_GAP'), NativePlayerTheme.transportGap.round());
      expect(
        kotlinInt('CONTROL_ICON'),
        NativePlayerTheme.controlIconSize.round(),
      );
      expect(kotlinInt('CONTROL_GAP'), NativePlayerTheme.controlGap.round());
      expect(kotlinInt('BADGE_MIN'), NativePlayerTheme.badgeMinSize.round());
      expect(kotlinInt('LOCK_ICON'), NativePlayerTheme.lockIconSize.round());
    });

    test('面板', () {
      expect(kotlinInt('PANEL_RIGHT'), NativePlayerTheme.panelRight.round());
      expect(
        kotlinInt('PANEL_TOP_OFFSET'),
        NativePlayerTheme.panelTopOffset.round(),
      );
      expect(
        kotlinInt('PANEL_BOTTOM_OFFSET'),
        NativePlayerTheme.panelBottomOffset.round(),
      );
      expect(kotlinInt('PANEL_PAD_H'), NativePlayerTheme.panelPadH.round());
      expect(kotlinInt('PANEL_PAD_V'), NativePlayerTheme.panelPadV.round());
      expect(kotlinInt('PANEL_CHECK_SLOT'), NativePlayerTheme.panelCheckSlot.round());
      expect(
        kotlinInt('ADJUST_LABEL_WIDTH'),
        NativePlayerTheme.adjustLabelWidth.round(),
      );
      expect(
        kotlinInt('ADJUST_VALUE_WIDTH'),
        NativePlayerTheme.adjustValueWidth.round(),
      );
      expect(
        kotlinInt('ADJUST_ROW_PAD_V'),
        NativePlayerTheme.adjustRowPadV.round(),
      );
      expect(
        kotlinInt('DECODE_PANEL_WIDTH'),
        NativePlayerTheme.decodePanelWidth.round(),
      );
      expect(
        kotlinInt('SEGMENT_CARD_WIDTH'),
        NativePlayerTheme.segmentCardWidth.round(),
      );
      expect(
        kotlinInt('SEGMENT_ROW_ICON'),
        NativePlayerTheme.segmentRowIconSize.round(),
      );
      expect(
        kotlinInt('SEGMENT_CHEVRON'),
        NativePlayerTheme.segmentChevronSize.round(),
      );
      expect(kotlinInt('AUTO_HIDE_MS'), NativePlayerTheme.autoHideMs);
    });

    test('面板宽度夹取比例与边界一致', () {
      // Dart 侧 panelWidthRatio/min/max 是唯一来源，Kotlin 用 dp 计算。
      expect(NativePlayerTheme.panelWidthRatio, closeTo(0.42, 1e-9));
      expect(NativePlayerTheme.panelMinWidth, 260);
      expect(NativePlayerTheme.panelMaxWidth, 320);
      expect(kotlin.contains('0.42f'), isTrue,
          reason: 'Kotlin 面板宽度比例需与 Dart panelWidthRatio 一致');
    });
  });

  group('Dart ↔ 鸿蒙（ArkTS NativePlayerPanel）', () {
    test('选中主色/着色/圆角/内边距', () {
      expect(arkts.contains('#6366F1'), isTrue,
          reason: '鸿蒙选中主色需与 Dart accent 一致');
      expect(arkts.contains('#1F1A1D23'), isTrue,
          reason: '鸿蒙面板着色需与 Dart panelTint 一致');
      // 圆角：常规面板 radiusPanel(16)；选集贴边左圆角 16（Flutter fullBleed）。
      expect(arkts.contains('topLeft: 16, bottomLeft: 16'), isTrue,
          reason: '鸿蒙选集面板左圆角需与 Dart radiusPanel 一致');
      expect(arkts.contains('PANEL_RADIUS = 16'), isTrue,
          reason: '鸿蒙常规面板圆角需与 Dart radiusPanel 一致');
      // 宽度：clamp(0.42×屏宽, 260, 320)（Flutter selectorPanelWidth）。
      expect(arkts.contains(".width('42%')"), isTrue,
          reason: '鸿蒙面板宽比例需与 Dart panelWidthRatio 一致');
      expect(arkts.contains('minWidth: 260, maxWidth: 320'), isTrue,
          reason: '鸿蒙面板宽夹取需与 Dart panelMin/MaxWidth 一致');
      expect(RegExp(r'right: 12').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板右距需与 Dart panelRight 一致');
      // 上/下距拆成具名常量后叠加安全区（Flutter safeTop+48 / 116+safeBottom）。
      expect(arkts.contains('const PANEL_PAD_TOP = 48'), isTrue,
          reason: '鸿蒙面板上距需与 Dart panelTopOffset 一致');
      expect(arkts.contains('const PANEL_PAD_BOTTOM = 116'), isTrue,
          reason: '鸿蒙面板下距需与 Dart panelBottomOffset 一致');
      expect(RegExp(r'left: 16, right: 16, top: 10, bottom: 4').hasMatch(arkts),
          isTrue,
          reason: '鸿蒙面板标题内边距需与 Flutter SelectorSidePanel 一致');
    });

    test('倍速档位与 Dart 侧一致', () {
      expect(
        arkts.contains('[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]'),
        isTrue,
        reason: '鸿蒙倍速档位需与 Flutter SpeedMenuPanel 一致',
      );
    });

    test('选项行对勾槽宽 18', () {
      expect(RegExp(r'\.width\(18\)').hasMatch(arkts), isTrue,
          reason: '鸿蒙对勾槽宽需与 Dart panelCheckSlot 一致');
    });

    test('解码模式当前值颜色与 Dart 一致', () {
      expect(arkts.contains('#A5B4FC'), isTrue,
          reason: '鸿蒙解码当前值颜色需与 Dart decodeCurrentText 一致');
    });
  });

  group('原生控制层交互完整性（防真机回归）', () {
    final view = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiNativePlayerView.ets',
    ).readAsStringSync();
    final host = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiMpvNativeHost.ets',
    ).readAsStringSync();
    final screen = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();

    test('鸿蒙底栏必须有锁控件（未锁 lock_open / 已锁 lock）', () {
      // 真机回归：只有 LockOnlyBar（锁定态）有锁钮，正常态底栏左侧空着，
      // 用户无法上锁。
      expect(view, contains('ICON_LOCK_OPEN'),
          reason: '鸿蒙底栏缺未锁态锁图标');
      expect(view, contains('ICON_LOCK'),
          reason: '鸿蒙底栏缺已锁态锁图标');
    });

    test('鸿蒙传输组不得 width 100%（否则播放键偏左不居中）', () {
      // 真机回归：Row({space:8}).justifyContent(FlexAlign.Start).width('100%')
      // 会撑满整行再左对齐，播放键明显偏左。
      final lines = view.split('\n');
      final idx = lines.indexWhere((l) => l.contains('this.TransportGlyph(this.prevGlyph()'));
      expect(idx, greaterThan(0), reason: '未找到鸿蒙传输组（prevGlyph）');
      // 取该 Row 起点到其 justify 声明之间的片段。
      var start = idx;
      while (start > 0 && !lines[start].contains('Row({ space: 8 })')) {
        start--;
      }
      var end = idx;
      while (end < lines.length && !lines[end].contains('justifyContent(FlexAlign.')) {
        end++;
      }
      final block = lines.sublist(start, end + 1).join('\n');
      expect(block.contains("width('100%')"), isFalse,
          reason: '鸿蒙传输组不应设 width 100%（会导致播放键偏左）');
      expect(block, contains('FlexAlign.Center'),
          reason: '鸿蒙传输组应居中');
    });

    test('鸿蒙底栏渐变方向必须自上而下（angle 180）', () {
      // 真机回归：angle 0 = 自左向右 → 整条横向压黑成硬边「黑幕」。
      final lines = view.split('\n');
      final idx = lines.indexWhere((l) => l.contains('this.ControlRow();'));
      expect(idx, greaterThan(0), reason: '未找到 ControlRow 调用');
      var end = idx;
      while (end < lines.length && !lines[end].contains('angle:')) {
        end++;
      }
      expect(end, lessThan(lines.length), reason: '底栏渐变未找到 angle');
      final angle = int.parse(RegExp(r'angle: (\d+)').firstMatch(lines[end])!.group(1)!);
      expect(angle, 180, reason: '鸿蒙底栏渐变应为自上而下（angle 180）');
    });

    test('鸿蒙可点击控件必须有按下反馈（stateStyles pressed）', () {
      // 真机回归：ArkUI 裸 Text 无按下视觉反馈 → 用户以为「点了没反应」。
      expect(view, contains('@Styles'),
          reason: '鸿蒙缺 @Styles 按下反馈定义');
      expect(RegExp(r'stateStyles\(\{ pressed:').hasMatch(view), isTrue,
          reason: '鸿蒙控件缺 stateStyles(pressed) 按下反馈');
      expect(RegExp(r'\.opacity\(0\.5\)').hasMatch(view), isTrue,
          reason: '按下反馈应含透明度变化');
    });

    test('鸿蒙 bridge 未就绪时命令必须入队而非丢弃', () {
      // 真机回归：bridge===null 时只 warn 就 return → 点击被静默丢弃。
      expect(host, contains('pendingCommands'),
          reason: '鸿蒙 host 缺待发命令队列');
      expect(host, contains('补发积压命令'),
          reason: '鸿蒙 host 未在 bridge 就绪后补发积压命令');
    });

    test('安卓图标容器必须容得下字形（防裁切残缺）', () {
      // 真机回归：badgeButton 图标容器仅 24dp，24sp 字形净高≈28dp → 上下裁切。
      expect(screen, contains('includeFontPadding = false'),
          reason: '安卓图标控件应关闭字体留白防裁切');
      final badgeBlock = RegExp(
        r'host\.addView\(iconButton\(codePoint, onClick\), lp\(dp\((\d+)\), dp\((\d+)\)',
      ).firstMatch(screen);
      expect(badgeBlock, isNotNull, reason: '未找到安卓 badgeButton 图标容器');
      expect(int.parse(badgeBlock!.group(1)!), greaterThanOrEqualTo(28),
          reason: '安卓角标图标容器需 ≥28dp（24sp 字形净高）');
    });

    test('安卓控件必须有按下反馈 + 命令队列（防点击无反应）', () {
      expect(screen, contains('applyPressFeedback'),
          reason: '安卓控件缺按下反馈');
      expect(RegExp(r'ACTION_DOWN').hasMatch(screen), isTrue,
          reason: '按下反馈应处理 ACTION_DOWN');
      final channelSrc = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'AndroidNativePlayerChannel.kt',
      ).readAsStringSync();
      expect(channelSrc, contains('pendingCommands'),
          reason: '安卓通道缺 Dart 订阅前的命令队列');
    });

    test('鸿蒙插件层命令不得丢弃（nativeUiSink 未就绪须入队）', () {
      // 真机回归：forwardCommand 在 sink==null 时只 warn 就丢 → 点击无反应。
      final plugin = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      ).readAsStringSync();
      expect(plugin, contains('pendingNativeUiCommands'),
          reason: '鸿蒙插件缺 nativeUi 命令队列');
      expect(plugin, contains('enqueueNativeUiCommand'),
          reason: '鸿蒙插件缺命令入队方法');
    });

    test('安卓玻璃采样源必须是 SurfaceView（防黑底面板回归）', () {
      // 真机回归：PixelCopy(window) 采到控件窗透明层 = 黑底；视频在
      // setZOrderOnTop 的 SurfaceView 图层，必须用 SurfaceView 重载。
      final glass = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'GlassBackdrop.kt',
      ).readAsStringSync();
      expect(RegExp(r'PixelCopy\.request\(\s*surface').hasMatch(glass), isTrue,
          reason: '玻璃采样必须走 PixelCopy(SurfaceView) 重载');
      expect(glass.contains('PixelCopy.request(\n                window'), isFalse,
          reason: '禁用 PixelCopy(Window)（采样源是透明控件窗 → 黑底）');
    });

    test('安卓锁定态必须整体隐藏控件层（只留锁钮）', () {
      // 真机回归：锁定分支只隐藏 transport/trailing → 顶栏/进度条仍显示。
      final block = RegExp(r'锁定态（对齐 Flutter _buildLockOnlyControls）[\s\S]{0,700}')
          .firstMatch(screen);
      expect(block, isNotNull, reason: '未找到锁定态渲染分支');
      final b = block!.group(0)!;
      expect(b, contains('topBar.visibility = GONE'));
      expect(b, contains('seekRow.visibility = GONE'));
    });

    test('安卓自适应必须真实收窄间距（禁 scale）', () {
      // 真机回归：scaleX/Y 只改绘制不改测量宽度 → 流式溢出仍出屏。
      expect(screen, contains('applyGroupGap'),
          reason: '自适应须真实收窄间距（applyGroupGap）');
      expect(screen.contains('trailingGroup.scaleX'), isFalse,
          reason: '禁用 scale 自适应（不改占位会出屏）');
    });

    test('选集卡片必须带 16:9 封面（两端对齐 Flutter EpisodeSelectPanel）', () {
      expect(screen, contains('NativeLogoLoader.load(this, ep.poster'),
          reason: '安卓选集卡片须加载封面图');
      final panel = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'NativePlayerPanel.ets',
      ).readAsStringSync();
      expect(panel, contains('Image(e.poster)'),
          reason: '鸿蒙选集卡片须渲染封面图');
      expect(panel, contains('aspectRatio(16 / 9)'),
          reason: '鸿蒙选集封面须 16:9');
    });

    test('房间分享按钮全链（对齐 Flutter showShare）', () {
      // 命令类 + 解析 + 两端发送 + Dart handler。
      final cmd = File(
        'lib/services/player/native/native_player_command.dart',
      ).readAsStringSync();
      expect(cmd, contains('class ShareRoom'));
      expect(cmd, contains("case 'shareRoom'"));
      final host = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiMpvNativeHost.ets',
      ).readAsStringSync();
      expect(host, contains("sendCommand('shareRoom'"));
      expect(screen, contains('shareButton'),
          reason: '安卓顶栏须有分享按钮');
    });

    test('fit 映射禁设 video-aspect-override（竖屏比例防回归）', () {
      // 该属性取值语义随 mpv 版本漂移（-1/no/0），设错把画面拉变形。
      // 断言属性**设置**（引号键），不误伤解释性注释。
      final adapter = File(
        'lib/services/player/mpv_player_adapter.dart',
      ).readAsStringSync();
      expect(adapter.contains("'video-aspect-override'"), isFalse,
          reason: 'applyVideoFit 禁设 video-aspect-override（版本语义漂移）');
    });

    test('安卓 .apply 不得接在 Runnable/object 表达式后（控件层 GONE 回归）', () {
      // 真机回归：glassSampleRunnable 的 object 表达式后接 .apply，Kotlin 解析
      // 到外层 this（根视图）→ 整个控件层被 setVisibility(GONE) →「只有画面
      // 没控件」。.apply 只能接在 View 声明后面。
      expect(screen, contains('panelScrim = View(context).apply'),
          reason: 'panelScrim 必须自带初始化（apply 接 View 声明）');
      final runnableBlock = RegExp(
        r'glassSampleRunnable = object : Runnable \{[\s\S]*?\n    \}',
      ).firstMatch(screen);
      expect(runnableBlock, isNotNull, reason: '未找到 glassSampleRunnable');
      expect(runnableBlock!.group(0)!.contains('.apply'), isFalse,
          reason: 'glassSampleRunnable（Runnable）后不得接 .apply（会命中根视图）');
    });

    test('鸿蒙控件定位禁用 position 百分比（跑位回归）', () {
      // 真机回归：尾组 .position({x:'100%', y:'50%'}) 的百分比基准是父容器
      // （Stack 高度不定）→ 控件跑到屏幕中部/屏外、点不到。定位一律走流式
      // 布局 + markAnchor 变换锚。
      expect(RegExp(r"\.position\(\{[^}]*x: '100%'").hasMatch(view), isFalse,
          reason: '鸿蒙控件禁止 position 百分比定位（须流式布局 + markAnchor）');
      // markAnchor 同样真实位移布局（debug26 回归），尾组禁用。
      expect(RegExp(r"markAnchor\(\{ x: '100%'").hasMatch(view), isFalse,
          reason: '鸿蒙尾组禁用 markAnchor（会把控件推出屏外）');
      expect(view, contains('adjustTopGap'),
          reason: '鸿蒙顶栏须真实收窄间距（adjustTopGap）');
      expect(view, contains('adjustBottomGap'),
          reason: '鸿蒙底栏须真实收窄间距（adjustBottomGap）');
    });
  });

  group('液态玻璃参数（三端一致，对齐 Flutter GlassConfig）', () {
    final glassKotlin = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerUi.kt',
    ).readAsStringSync();
    final glassArkts = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerPanel.ets',
    ).readAsStringSync();

    test('模糊半径 20 与饱和度 1.6 三端一致', () {
      expect(glassKotlin, contains('GLASS_BLUR_RADIUS = 20f'));
      expect(glassKotlin, contains('GLASS_SATURATION = 1.6f'));
      expect(glassArkts, contains('GLASS_BLUR_RADIUS = 20'));
      expect(glassArkts, contains('GLASS_SATURATION = 1.6'));
      final theme = File(
        'lib/services/player/native/native_player_theme.dart',
      ).readAsStringSync();
      expect(theme, contains('glassBlurRadius = 20'));
      expect(theme, contains('glassSaturation = 1.6'));
    });

    test('鸿蒙面板必须用 backgroundEffect 真模糊（非 tint-only）', () {
      expect(
        RegExp(r'backgroundEffect\(\{ radius: GLASS_BLUR_RADIUS, saturation: GLASS_SATURATION \}\)')
            .hasMatch(glassArkts),
        isTrue,
        reason: '鸿蒙面板玻璃须 backgroundEffect(radius/saturation) 模糊背后视频',
      );
    });

    test('安卓玻璃降级链（采样失败不抛出，黑屏红线）', () {
      final glass = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'GlassBackdrop.kt',
      ).readAsStringSync();
      expect(glass, contains('createOrNull'),
          reason: '玻璃创建须有安全工厂（异常返回 null 降级）');
      expect(glass, contains('PixelCopy'),
          reason: '方案 A 玻璃须 PixelCopy 采样视频帧');
      expect(glass, contains('GLASS_REFRACTION_ZOOM'),
          reason: '玻璃须有折射带放大（液态玻璃折射观感）');
    });
  });
}

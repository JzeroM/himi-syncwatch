import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：TV 模式顶栏时钟与标题让位。
///
/// ## 需求（用户明确）
///
/// 1. **时钟只做 TV 模式**——其他平台/模式不渲染
/// 2. 设置里**开启**时：时钟放左上角，**标题给时钟让位**
/// 3. 设置里**关闭**时：标题回到原来的左上位置，**不让位**
///
/// ## 修复前的 bug
///
/// `642` 把时钟从右贴边移到左贴边，但 `reserveClockSpace` 的预留区仍留在
/// `Row` **末尾（右侧）**，且调用点硬编码 `false`。结果 TV 标题从 x=12
/// 开始绘制，与左上角时钟（x∈[12,112]）**完全重叠**——控件显示时标题盖住
/// 时钟，控件隐藏后顶栏消失时钟才露出来（用户反馈的现象）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String topBar;
  late String clock;
  late String player;
  late String general;

  setUpAll(() {
    topBar = read('lib/screens/player/widgets/player_top_bar.dart');
    clock = read('lib/screens/player/widgets/player_clock.dart');
    player = read('lib/screens/player/player_screen.dart');
    general = read('lib/screens/settings/general_settings_screen.dart');
  });

  group('1. 时钟只在 TV 模式渲染', () {
    test('1.1 PlayerClockLayer 非 TV 直接返回空', () {
      expect(codeOnly(clock), contains('if (!tvMode || !format.enabled)'));
      expect(codeOnly(clock), contains('return const SizedBox.shrink()'));
    });

    test('1.2 时钟关闭（off）时不渲染', () {
      final format = read('lib/models/top_bar_clock_format.dart');
      expect(format, contains('bool get enabled => this != off'));
    });

    test('1.3 渲染入口传入 tvMode', () {
      expect(codeOnly(player), contains('tvMode: videoAreaTvMode'));
    });

    test('1.4 设置项只在 TV 模式可见', () {
      // 「TV 与遥控」分组内的 `if (settings.tvMode)` 门禁
      final idx = general.indexOf('topBarClockSetting');
      expect(idx, greaterThan(0));
      final before = general.substring((idx - 400).clamp(0, idx), idx);
      expect(before, contains('if (settings.tvMode)'));
    });
  });

  group('2. 开启时标题让位（预留区在左侧）', () {
    test('2.1 预留区在 Row 开头（showBack 之前）', () {
      final rowIdx = codeOnly(topBar).indexOf('child: Row(');
      expect(rowIdx, greaterThan(0));
      final block = codeOnly(topBar).substring(rowIdx, rowIdx + 900);
      final reserveIdx = block.indexOf('playerClockSpace');
      final backIdx = block.indexOf('playerBackButton');
      expect(reserveIdx, greaterThan(0), reason: '应有预留 SizedBox');
      expect(backIdx, greaterThan(0));
      expect(reserveIdx, lessThan(backIdx),
          reason: '预留区必须在返回按钮之前（左侧）');
    });

    test('2.2 预留宽度覆盖时钟宽度 + 间距', () {
      // 时钟宽 100（PlayerClockLayer 的 width），预留 112 = 100 + 12 间距
      expect(clock, contains('width: 100'));
      final idx = topBar.indexOf('playerClockSpace');
      final block = topBar.substring(idx, idx + 200);
      expect(block, contains('width: 112'));
    });

    test('2.3 Row 末尾不再有旧的右侧预留', () {
      final code = codeOnly(topBar);
      final lastShare = code.lastIndexOf('playerShareButton');
      expect(lastShare, greaterThan(0));
      final tail = code.substring(lastShare);
      expect(tail, isNot(contains('playerClockSpace')),
          reason: '旧的右侧预留块必须删除');
    });

    test('2.4 调用点 = TV 模式 && 时钟开启', () {
      expect(codeOnly(player),
          contains('reserveClockSpace: tvMode && clockFormat.enabled'));
      // 不得再硬编码 false
      expect(codeOnly(player), isNot(contains('reserveClockSpace: false')));
    });

    test('2.5 顶栏订阅了时钟格式（否则不会随设置变化）', () {
      final idx = player.indexOf('Widget _buildTopBar()');
      final block = player.substring(idx, idx + 700);
      expect(block, contains('clockFormat: s.topBarClockFormat'));
      expect(block, contains(':clockFormat'));
    });
  });

  group('3. 关闭时标题不让位（回到最左）', () {
    test('3.1 reserveClockSpace 依赖 clockFormat.enabled', () {
      // 时钟 off → enabled=false → 预留为 false → 标题从 x=12 开始
      expect(codeOnly(player),
          contains('reserveClockSpace: tvMode && clockFormat.enabled'));
    });

    test('3.2 预留是条件渲染（false 时完全不占位）', () {
      final idx = topBar.indexOf('if (reserveClockSpace)');
      expect(idx, greaterThan(0));
      // `if` 直接包住 SizedBox（不是恒渲染再调宽度）
      final block = topBar.substring(idx, idx + 160);
      expect(block, contains('SizedBox'));
    });
  });

  group('4. 设置文案与实际位置一致', () {
    test('4.1 副标题写「左上角」而非「最右侧」', () {
      expect(general, contains('播放器左上角显示系统时间'));
      expect(general, isNot(contains('播放器顶栏最右侧显示系统时间')));
    });
  });
}

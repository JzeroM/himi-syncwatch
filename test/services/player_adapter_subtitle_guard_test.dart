import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

import '../helpers/test_fakes.dart';

/// 字幕滑杆原生崩溃（Windows）修复的守卫回归测试。
///
/// 背景：字幕样式滑杆 → `_player.setProperty('subtitle.scale'/'subtitle.margin.y')`。
/// mdk/fvp 的 setProperty 是裸 FFI，dispose 后会 use-after-free；Windows 上
/// HDR 自动路由重建引擎时 `_player` 会短暂指向已释放的旧引擎 → 拖滑杆闪退。
/// 修复分两层：
///  1. 播放器页门控：引擎重建中不再写入（[PlayerScreen.canWriteSubtitleStyle]）
///  2. 适配器守卫：释放后 setProperty 不再触达原生对象
void main() {
  group('PlayerScreen.canWriteSubtitleStyle 门控', () {
    test('正常态放行', () {
      expect(
        PlayerScreen.canWriteSubtitleStyle(
          mounted: true,
          switchingEngine: false,
        ),
        isTrue,
      );
    });

    test('页面已销毁 → 禁止', () {
      expect(
        PlayerScreen.canWriteSubtitleStyle(
          mounted: false,
          switchingEngine: false,
        ),
        isFalse,
      );
    });

    test('引擎重建中 → 禁止（_player 可能指向旧引擎）', () {
      expect(
        PlayerScreen.canWriteSubtitleStyle(
          mounted: true,
          switchingEngine: true,
        ),
        isFalse,
      );
    });

    test('销毁 + 重建中 → 禁止', () {
      expect(
        PlayerScreen.canWriteSubtitleStyle(
          mounted: false,
          switchingEngine: true,
        ),
        isFalse,
      );
    });
  });

  group('适配器释放后 setProperty 守卫契约', () {
    test('未释放时写入生效', () {
      final player = FakePlayerAdapter();
      player.setProperty('subtitle.scale', '1.20');

      expect(player.attempts, ['subtitle.scale']);
      expect(player.written['subtitle.scale'], '1.20');
      expect(player.getProperty('subtitle.scale'), '1.20');
    });

    test('释放后不再写入原生（use-after-free 防护）', () {
      final player = FakePlayerAdapter(disposed: true);
      player.setProperty('subtitle.scale', '2.00');
      player.setProperty('subtitle.margin.y', '40');

      expect(player.attempts, ['subtitle.scale', 'subtitle.margin.y']);
      expect(player.written, isEmpty, reason: '释放后写入必须被守卫吞掉');
      expect(player.getProperty('subtitle.scale'), isNull);
    });
  });
}

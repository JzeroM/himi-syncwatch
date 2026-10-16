import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/stream_stall_guard.dart';

void main() {
  group('StreamStallGuard（缓冲 watchdog 真卡死判定）', () {
    test('位置推进超过阈值 → 仍视为播放中（不重载）', () {
      expect(StreamStallGuard.progressed(5000, 6200), isTrue);
      expect(StreamStallGuard.progressed(0, 501), isTrue);
    });

    test('位置推进不超过阈值 → 判定为卡死（可重载）', () {
      expect(StreamStallGuard.progressed(5000, 5000), isFalse);
      expect(StreamStallGuard.progressed(5000, 5300), isFalse);
      // 边界：恰好等于阈值不算推进
      expect(StreamStallGuard.progressed(5000, 5500), isFalse);
    });

    test('位置回退（seek 回退 / 归零）不算推进', () {
      expect(StreamStallGuard.progressed(5000, 4000), isFalse);
      expect(StreamStallGuard.progressed(5000, 0), isFalse);
    });

    test('阈值常量为 500ms', () {
      expect(StreamStallGuard.progressThresholdMs, 500);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/track_selection_queue.dart';

void main() {
  group('PendingTrackSelection（轨表异步就绪前的选轨暂存）', () {
    test('轨表为空：暂存请求，不提前下发', () {
      final queue = PendingTrackSelection()..request(<int>[2]);

      expect(queue.hasPending, isTrue);
      expect(queue.takeReady(0), isNull);
      expect(queue.hasPending, isTrue, reason: '未就绪时请求应保留');
    });

    test('轨表就绪且下标有效：取出一次并清空', () {
      final queue = PendingTrackSelection()..request(<int>[2]);

      expect(queue.takeReady(3), 2);
      expect(queue.hasPending, isFalse);
      expect(queue.takeReady(3), isNull, reason: '同一请求不重复下发');
    });

    test('下标暂时越界：保留请求，等待后续轨表扩展', () {
      final queue = PendingTrackSelection()..request(<int>[2]);

      expect(queue.takeReady(2), isNull);
      expect(queue.hasPending, isTrue);

      expect(queue.takeReady(3), 2, reason: '外挂轨追加后应可下发');
    });

    test('多次 request 以后一次为准', () {
      final queue = PendingTrackSelection()
        ..request(<int>[1])
        ..request(<int>[2]);

      expect(queue.takeReady(3), 2);
    });

    test('媒体切换 clear 后旧请求不再下发', () {
      final queue = PendingTrackSelection()..request(<int>[1]);
      queue.clear();

      expect(queue.hasPending, isFalse);
      expect(queue.takeReady(3), isNull);
    });

    test('空选择不产生待下发请求', () {
      final queue = PendingTrackSelection()..request(const <int>[]);

      expect(queue.requested, isNull);
      expect(queue.hasPending, isFalse);
      expect(queue.takeReady(3), isNull);
    });
  });
}

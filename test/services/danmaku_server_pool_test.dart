import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_server_pool.dart';

void main() {
  group('runDanmakuServers 优先级仲裁', () {
    test('高优先级先到立即返回（低优先级挂起不拖累）', () async {
      final gate = Completer<void>();
      final winner = await runDanmakuServers<String>(
        count: 2,
        run: (i) async {
          if (i == 0) return 'high';
          await gate.future; // 低优先级挂起
          return 'low';
        },
      );
      expect(winner?.index, 0);
      expect(winner?.result, 'high');
      gate.complete();
    });

    test('低优先级先到也等高优先级定局（高命中则高胜）', () async {
      final highGate = Completer<void>();
      final future = runDanmakuServers<String>(
        count: 2,
        run: (i) async {
          if (i == 0) {
            await highGate.future;
            return 'high-late';
          }
          return 'low-fast';
        },
      );
      // 低先到但不能立即采用；给高一点时间定局后放行
      await Future<void>.delayed(const Duration(milliseconds: 20));
      highGate.complete();
      final winner = await future;
      expect(winner?.index, 0);
      expect(winner?.result, 'high-late');
    });

    test('高优先级未命中 → 低优先级补位', () async {
      final winner = await runDanmakuServers<String>(
        count: 2,
        run: (i) async {
          if (i == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return null;
          }
          return 'low-fast';
        },
      );
      expect(winner?.index, 1);
      expect(winner?.result, 'low-fast');
    });

    test('全部未命中 → null', () async {
      final winner = await runDanmakuServers<String>(
        count: 3,
        run: (i) async => null,
      );
      expect(winner, isNull);
    });

    test('无源 → null', () async {
      final winner = await runDanmakuServers<String>(
        count: 0,
        run: (i) async => 'x',
      );
      expect(winner, isNull);
    });
  });

  group('超时兜底（全局超时语义）', () {
    test('挂起源按未命中，其余正常胜出', () async {
      final hang = Completer<String?>(); // 永不完结（等价挂起源）
      final winner = await runDanmakuServers<String>(
        count: 2,
        timeout: const Duration(milliseconds: 50),
        run: (i) async {
          if (i == 0) return hang.future;
          return 'ok';
        },
      );
      expect(winner?.index, 1);
      expect(winner?.result, 'ok');
    });

    test('全部挂起 → 超时后 null（不永久阻塞）', () async {
      final hang = Completer<String?>();
      final winner = await runDanmakuServers<String>(
        count: 2,
        timeout: const Duration(milliseconds: 50),
        run: (i) async => hang.future,
      );
      expect(winner, isNull);
    });
  });

  group('并发写安全（匹配记忆）', () {
    test('并发 put 不丢条目（写串行化）', () async {
      final tmp = await Directory.systemTemp.createTemp('mem_concurrent');
      final memory = LocalDanmakuMatchMemory(directory: tmp.path);
      await Future.wait([
        for (var i = 0; i < 20; i++)
          memory.put(
            itemKey: 'k$i',
            record: DanmakuMatchRecord(episodeId: i),
          ),
      ]);
      final all = await memory.all();
      expect(all, hasLength(20), reason: '并发 put 竞态会丢条目');
      await tmp.delete(recursive: true);
    });
  });
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/poster_tone_resolver.dart';

void main() {
  group('PosterToneResolver（698 N8-A 色调取色调度）', () {
    test('ensure 取色成功 → trio 就绪并通知；同 URL 不重发', () async {
      var calls = 0;
      var notified = 0;
      final resolver = PosterToneResolver(
        extract: (url, {headers}) async {
          calls++;
          return const [Color(0xFF112233), Color(0xFF223344), Color(0xFF001122)];
        },
        onChanged: () => notified++,
      );

      resolver.ensure('http://x/a.jpg', headers: {'X-Emby-Token': 't'});
      expect(resolver.trio, isNull, reason: '异步完成前为 null（调用方走兜底）');
      await Future<void>.delayed(Duration.zero);
      expect(resolver.trio, isNotNull);
      expect(notified, 1);

      resolver.ensure('http://x/a.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: '同 URL 幂等不重发');
      expect(notified, 1);
    });

    test('换 URL 立即清空 trio；旧结果晚到被丢弃（seq 竞态令牌）', () async {
      final pending = <String, Completer<List<Color>?>>{};
      final resolver = PosterToneResolver(
        extract: (url, {headers}) {
          final c = Completer<List<Color>?>();
          pending[url] = c;
          return c.future;
        },
      );

      resolver.ensure('http://x/a.jpg');
      resolver.ensure('http://x/b.jpg');
      expect(resolver.trio, isNull, reason: '换 URL 当帧清空');

      // 旧图（a.jpg）晚到：不得覆写。
      pending['http://x/a.jpg']!
          .complete(const [Color(0xFFAA0000), Color(0xFFAA0000), Color(0xFFAA0000)]);
      await Future<void>.delayed(Duration.zero);
      expect(resolver.trio, isNull);

      pending['http://x/b.jpg']!
          .complete(const [Color(0xFF0000AA), Color(0xFF0000AA), Color(0xFF0000AA)]);
      await Future<void>.delayed(Duration.zero);
      expect(resolver.trio!.first, const Color(0xFF0000AA));
    });

    test('null/空 URL：清空 trio 且不发请求', () async {
      var calls = 0;
      final resolver = PosterToneResolver(
        extract: (url, {headers}) async {
          calls++;
          return const [Color(0xFF112233), Color(0xFF112233), Color(0xFF112233)];
        },
      );
      resolver.ensure('http://x/a.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(resolver.trio, isNotNull);

      resolver.ensure(null);
      expect(resolver.trio, isNull);
      resolver.ensure('');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: '空 URL 不触发取色');
    });

    test('取色失败（null）→ trio 保持 null（调用方走主题色兜底）', () async {
      final resolver = PosterToneResolver(
        extract: (url, {headers}) async => null,
      );
      resolver.ensure('http://x/a.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(resolver.trio, isNull);
    });
  });
}

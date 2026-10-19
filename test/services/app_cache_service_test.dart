import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/cache/app_cache_service.dart';
import 'package:himi_syncwatch/services/cache/cache_models.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_caches.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';

const _comments = [
  DanmakuComment(
      time: 1, mode: DanmakuMode.scroll, color: 0xFFFFFFFF, text: 'a'),
  DanmakuComment(time: 2, mode: DanmakuMode.top, color: 0xFFFFFFFF, text: 'b'),
];

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('himi_cache_test_');
    DanmakuCaches.clear();
  });

  tearDown(() async {
    DanmakuCaches.clear();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeFile(String relative, int bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 1));
    return file;
  }

  AppCacheService service({
    Future<void> Function()? clearImageCache,
    void Function()? clearLogMemory,
    void Function()? clearDanmaku,
  }) =>
      AppCacheService(
        temporaryDirectory: () async => temp,
        imageCacheDirName: 'himiCachedImageData',
        clearImageCache: clearImageCache ?? () async {},
        clearLogMemory: clearLogMemory ?? () {},
        clearDanmaku: clearDanmaku ?? () {},
      );

  group('scan', () {
    test('按实际路径统计图片、临时文件、日志与弹幕条数', () async {
      await writeFile('himiCachedImageData/a.jpg', 100);
      await writeFile('himiCachedImageData/b.jpg', 200);
      await writeFile('himi_qr.png', 10);
      await writeFile('himi_qr_123.png', 20);
      await writeFile('himi_sub_shift_9.srt', 30);
      await writeFile('other.tmp', 40);
      await writeFile('himi_runtime.log', 50);
      await writeFile('himi_logs.log', 70);
      DanmakuCaches.episode.put('a', 1);
      DanmakuCaches.comments.put('b', _comments);

      final snapshot = await service().scan();

      expect(snapshot.statOf(CacheCategory.images).bytes, 300);
      expect(snapshot.statOf(CacheCategory.images).itemCount, 2);
      expect(snapshot.statOf(CacheCategory.temp).bytes, 60);
      expect(snapshot.statOf(CacheCategory.temp).itemCount, 3);
      expect(snapshot.statOf(CacheCategory.logs).bytes, 120);
      expect(snapshot.statOf(CacheCategory.logs).itemCount, 2);
      expect(snapshot.statOf(CacheCategory.danmaku).itemCount, 2);
      expect(snapshot.totalDiskBytes, 480);
      expect(snapshot.totalDanmakuCount, 2);
      expect(
        snapshot.diskStats.map((entry) => entry.key),
        [CacheCategory.images, CacheCategory.temp, CacheCategory.logs],
      );
      expect(snapshot.hasAny, isTrue);
    });

    test('目录不存在时返回零值', () async {
      final snapshot = await service().scan();
      expect(snapshot.totalDiskBytes, 0);
      expect(snapshot.totalDanmakuCount, 0);
      expect(snapshot.hasAny, isFalse);
    });
  });

  group('clear', () {
    test('临时文件只删白名单，保留其他文件', () async {
      final qr = await writeFile('himi_qr_123.png', 10);
      final subtitle = await writeFile('himi_sub_shift_1.ass', 20);
      final other = await writeFile('other.tmp', 30);

      final result = await service().clear(CacheCategory.temp);

      expect(result.success, isTrue);
      expect(await qr.exists(), isFalse);
      expect(await subtitle.exists(), isFalse);
      expect(await other.exists(), isTrue);
    });

    test('诊断日志删文件并清空内存日志', () async {
      final runtime = await writeFile('himi_runtime.log', 50);
      final export = await writeFile('himi_logs.log', 70);
      var memoryCleared = false;

      final result = await service(
        clearLogMemory: () => memoryCleared = true,
      ).clear(CacheCategory.logs);

      expect(result.success, isTrue);
      expect(await runtime.exists(), isFalse);
      expect(await export.exists(), isFalse);
      expect(memoryCleared, isTrue);
    });

    test('图片缓存调用管理器清理回调', () async {
      var imageCleared = false;
      final result = await service(
        clearImageCache: () async => imageCleared = true,
      ).clear(CacheCategory.images);

      expect(result.success, isTrue);
      expect(imageCleared, isTrue);
    });

    test('弹幕缓存清空静态容器', () async {
      DanmakuCaches.episode.put('a', 1);
      DanmakuCaches.comments.put('b', _comments);

      final result = await service(
        clearDanmaku: DanmakuCaches.clear,
      ).clear(CacheCategory.danmaku);

      expect(result.success, isTrue);
      expect(DanmakuCaches.totalCount, 0);
    });

    test('清理全部覆盖四类并汇总失败', () async {
      await writeFile('himiCachedImageData/a.jpg', 100);
      await writeFile('himi_qr.png', 10);
      await writeFile('himi_runtime.log', 50);
      DanmakuCaches.episode.put('a', 1);
      DanmakuCaches.comments.put('b', _comments);
      var imageCleared = false;
      var logMemoryCleared = false;
      var danmakuCleared = false;

      final result = await service(
        clearImageCache: () async {
          imageCleared = true;
          await Directory(
            '${temp.path}${Platform.pathSeparator}himiCachedImageData',
          ).delete(recursive: true);
        },
        clearLogMemory: () => logMemoryCleared = true,
        clearDanmaku: () {
          danmakuCleared = true;
          DanmakuCaches.clear();
        },
      ).clearAll();

      expect(result.success, isTrue);
      expect(imageCleared, isTrue);
      expect(logMemoryCleared, isTrue);
      expect(danmakuCleared, isTrue);
      expect(DanmakuCaches.totalCount, 0);
      final snapshot = await service().scan();
      expect(snapshot.totalDiskBytes, 0);
      expect(snapshot.totalDanmakuCount, 0);
    });
  });

  group('formatBytes', () {
    test('边界与单位', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
      expect(formatBytes(1573888), '1.50 MB');
    });
  });
}

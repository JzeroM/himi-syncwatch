import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'package:himi_syncwatch/services/cache/cache_models.dart';
import 'package:himi_syncwatch/services/cache/himi_image_cache_manager.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_caches.dart';
import 'package:himi_syncwatch/services/log_service.dart';

abstract class CacheService {
  Future<CacheSnapshot> scan();

  Future<CacheClearResult> clear(CacheCategory category);

  Future<CacheClearResult> clearAll();
}

class AppCacheService implements CacheService {
  AppCacheService({
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function()? clearImageCache,
    void Function()? clearLogMemory,
    void Function()? clearDanmaku,
    String? imageCacheDirName,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _clearImageCache = clearImageCache ?? _defaultClearImageCache,
        _clearLogMemory = clearLogMemory ?? LogService().clear,
        _clearDanmaku = clearDanmaku ?? DanmakuCaches.clear,
        _imageCacheDirName =
            imageCacheDirName ?? HimiImageCacheManager.activeKey;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function() _clearImageCache;
  final void Function() _clearLogMemory;
  final void Function() _clearDanmaku;
  final String _imageCacheDirName;

  static final RegExp _qrPattern = RegExp(r'^himi_qr(?:_\d+)?\.png$');
  static final RegExp _subtitlePattern =
      RegExp(r'^himi_sub_shift_\d+\.(?:srt|ass)$');

  static Future<void> _defaultClearImageCache() async {
    try {
      await HimiImageCacheManager.activeManager.emptyCache();
    } finally {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    }
  }

  @override
  Future<CacheSnapshot> scan() async {
    final temp = await _temporaryDirectory();
    final images = await _scanDirectory(
      Directory(_join(temp.path, _imageCacheDirName)),
      recursive: true,
    );
    final temporary = await _scanMatchingFiles(temp, _isTempFileName);
    final logs = await _scanFiles([
      File(_join(temp.path, 'himi_runtime.log')),
      File(_join(temp.path, 'himi_logs.log')),
    ]);

    return CacheSnapshot(stats: {
      CacheCategory.images: images,
      CacheCategory.danmaku: CacheStat(
        bytes: 0,
        itemCount: DanmakuCaches.totalCount,
      ),
      CacheCategory.temp: temporary,
      CacheCategory.logs: logs,
    });
  }

  @override
  Future<CacheClearResult> clear(CacheCategory category) async {
    switch (category) {
      case CacheCategory.images:
        try {
          await _clearImageCache();
          return const CacheClearResult();
        } catch (e) {
          return CacheClearResult(failures: [e.toString()]);
        }
      case CacheCategory.danmaku:
        _clearDanmaku();
        return const CacheClearResult();
      case CacheCategory.temp:
        final temp = await _temporaryDirectory();
        return _deleteMatchingFiles(temp, _isTempFileName);
      case CacheCategory.logs:
        final temp = await _temporaryDirectory();
        final result = await _deleteFiles([
          File(_join(temp.path, 'himi_runtime.log')),
          File(_join(temp.path, 'himi_logs.log')),
        ]);
        _clearLogMemory();
        return result;
    }
  }

  @override
  Future<CacheClearResult> clearAll() async {
    final failures = <String>[];
    for (final category in CacheCategory.values) {
      try {
        final result = await clear(category);
        failures.addAll(result.failures);
      } catch (e) {
        failures.add('$category: $e');
      }
    }
    return CacheClearResult(failures: failures);
  }

  static bool _isTempFileName(String name) =>
      _qrPattern.hasMatch(name) || _subtitlePattern.hasMatch(name);

  static String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  static String _baseName(String path) =>
      path.split(Platform.pathSeparator).last;

  Future<CacheStat> _scanDirectory(
    Directory directory, {
    required bool recursive,
  }) async {
    if (!await directory.exists()) return CacheStat.zero;
    var bytes = 0;
    var count = 0;
    await for (final entity
        in directory.list(recursive: recursive, followLinks: false)) {
      if (entity is! File) continue;
      try {
        bytes += await entity.length();
        count++;
      } catch (_) {}
    }
    return CacheStat(bytes: bytes, itemCount: count);
  }

  Future<CacheStat> _scanMatchingFiles(
    Directory directory,
    bool Function(String name) matches,
  ) async {
    if (!await directory.exists()) return CacheStat.zero;
    var bytes = 0;
    var count = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!matches(_baseName(entity.path))) continue;
      try {
        bytes += await entity.length();
        count++;
      } catch (_) {}
    }
    return CacheStat(bytes: bytes, itemCount: count);
  }

  Future<CacheStat> _scanFiles(Iterable<File> files) async {
    var bytes = 0;
    var count = 0;
    for (final file in files) {
      try {
        if (!await file.exists()) continue;
        bytes += await file.length();
        count++;
      } catch (_) {}
    }
    return CacheStat(bytes: bytes, itemCount: count);
  }

  Future<CacheClearResult> _deleteMatchingFiles(
    Directory directory,
    bool Function(String name) matches,
  ) async {
    if (!await directory.exists()) return const CacheClearResult();
    final failures = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!matches(_baseName(entity.path))) continue;
      try {
        await entity.delete();
      } catch (_) {
        failures.add(entity.path);
      }
    }
    return CacheClearResult(failures: failures);
  }

  Future<CacheClearResult> _deleteFiles(Iterable<File> files) async {
    final failures = <String>[];
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        failures.add(file.path);
      }
    }
    return CacheClearResult(failures: failures);
  }
}

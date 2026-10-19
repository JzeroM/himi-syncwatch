import 'package:himi_syncwatch/services/cache/app_cache_service.dart';
import 'package:himi_syncwatch/services/cache/cache_models.dart';

class FakeAppCacheService implements CacheService {
  FakeAppCacheService(this.snapshot);

  CacheSnapshot snapshot;
  final List<CacheCategory> cleared = [];
  int clearAllCount = 0;
  bool failScan = false;
  bool failClear = false;

  @override
  Future<CacheSnapshot> scan() async {
    if (failScan) throw StateError('scan failed');
    return snapshot;
  }

  @override
  Future<CacheClearResult> clear(CacheCategory category) async {
    cleared.add(category);
    if (failClear) return CacheClearResult(failures: ['failed']);
    final stats = Map<CacheCategory, CacheStat>.from(snapshot.stats);
    stats[category] = CacheStat.zero;
    snapshot = CacheSnapshot(stats: stats);
    return const CacheClearResult();
  }

  @override
  Future<CacheClearResult> clearAll() async {
    clearAllCount++;
    if (failClear) return CacheClearResult(failures: ['failed']);
    snapshot = CacheSnapshot(stats: {
      for (final category in CacheCategory.values) category: CacheStat.zero,
    });
    return const CacheClearResult();
  }
}

CacheSnapshot cacheSnapshot({
  int images = 0,
  int danmaku = 0,
  int temp = 0,
  int logs = 0,
}) =>
    CacheSnapshot(stats: {
      CacheCategory.images:
          CacheStat(bytes: images, itemCount: images > 0 ? 1 : 0),
      CacheCategory.danmaku: CacheStat(bytes: 0, itemCount: danmaku),
      CacheCategory.temp: CacheStat(bytes: temp, itemCount: temp > 0 ? 1 : 0),
      CacheCategory.logs: CacheStat(bytes: logs, itemCount: logs > 0 ? 1 : 0),
    });

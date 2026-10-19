enum CacheCategory { images, danmaku, temp, logs }

extension CacheCategoryInfo on CacheCategory {
  bool get isMemory => this == CacheCategory.danmaku;
}

class CacheStat {
  const CacheStat({required this.bytes, required this.itemCount});

  static const zero = CacheStat(bytes: 0, itemCount: 0);

  final int bytes;
  final int itemCount;

  bool get isEmpty => bytes == 0 && itemCount == 0;
}

class CacheSnapshot {
  CacheSnapshot(
      {required Map<CacheCategory, CacheStat> stats, DateTime? scannedAt})
      : stats = Map.unmodifiable(stats),
        scannedAt = scannedAt ?? DateTime.now();

  final Map<CacheCategory, CacheStat> stats;
  final DateTime scannedAt;

  CacheStat statOf(CacheCategory category) => stats[category] ?? CacheStat.zero;

  List<MapEntry<CacheCategory, CacheStat>> get diskStats => [
        for (final category in CacheCategory.values)
          if (!category.isMemory) MapEntry(category, statOf(category)),
      ];

  int get totalDiskBytes => diskStats.fold(
        0,
        (sum, entry) => sum + entry.value.bytes,
      );

  int get totalDanmakuCount => statOf(CacheCategory.danmaku).itemCount;

  bool get hasAny =>
      totalDiskBytes > 0 ||
      totalDanmakuCount > 0 ||
      CacheCategory.values.any((category) => !statOf(category).isEmpty);
}

class CacheClearResult {
  const CacheClearResult({this.failures = const []});

  final List<String> failures;

  bool get success => failures.isEmpty;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final digits = unit == 1 ? 1 : 2;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

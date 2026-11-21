import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';

/// 评分徽章缓存条目（698 N7-I）：结果 + 写入时间 + 是否有数据。
class RatingsCacheEntry {
  const RatingsCacheEntry({
    required this.badges,
    required this.at,
    required this.hasData,
  });

  final List<HeroRatingBadge> badges;
  final DateTime at;

  /// true = 有分（TTL 长）；false = 该源确认无数据（TTL 短，之后自动重查）。
  final bool hasData;

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'hasData': hasData,
        'badges': [
          for (final b in badges) [b.platform.name, b.display],
        ],
      };

  static RatingsCacheEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final atMs = json['at'] as num?;
      final raw = json['badges'];
      if (atMs == null || raw is! List) return null;
      final badges = <HeroRatingBadge>[];
      for (final row in raw) {
        if (row is! List || row.length < 2) continue;
        final platform = RatingPlatform.values
            .where((p) => p.name == row[0])
            .firstOrNull;
        if (platform == null) continue;
        badges.add(HeroRatingBadge(platform, '${row[1]}'));
      }
      return RatingsCacheEntry(
        badges: badges,
        at: DateTime.fromMillisecondsSinceEpoch(atMs.toInt()),
        hasData: json['hasData'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 评分徽章缓存抽象（698 N7-I）：命中即零网络瞬时出徽章。
///
/// 只缓存**成功**结果（含「确认无数据」空结果）；失败（源异常/反爬拦截）
/// 绝不写缓存——保留自动重试语义。
abstract class RatingsCacheStore {
  Future<RatingsCacheEntry?> read(String key);
  Future<void> write(String key, RatingsCacheEntry entry);
}

/// 内存实现：测试默认；不触平台通道。
class MemoryRatingsCacheStore implements RatingsCacheStore {
  final Map<String, RatingsCacheEntry> _entries = {};

  @override
  Future<RatingsCacheEntry?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, RatingsCacheEntry entry) async {
    _entries[key] = entry;
  }
}

/// 持久实现（698 N7-I）：沿用仓内设置持久化惯例（FlutterSecureStorage
/// 单键 JSON）。跨启动复用评分结果——重启后徽章行瞬时出全，豆瓣/Letterboxd
/// 不再重复爬。条目超 [maxEntries] 淘汰最旧。
class SecureRatingsCacheStore implements RatingsCacheStore {
  SecureRatingsCacheStore({
    FlutterSecureStorage? storage,
    this.maxEntries = 400,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const String _storageKey = 'himi_ratings_cache';

  final FlutterSecureStorage _storage;
  final int maxEntries;

  Map<String, RatingsCacheEntry>? _cache;

  Future<Map<String, RatingsCacheEntry>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await _storage.read(key: _storageKey);
    final out = <String, RatingsCacheEntry>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          for (final e in json.entries) {
            final entry = RatingsCacheEntry.fromJson(e.value);
            if (entry != null) out['${e.key}'] = entry;
          }
        }
      } catch (_) {
        // 脏数据当空缓存处理。
      }
    }
    return _cache = out;
  }

  @override
  Future<RatingsCacheEntry?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, RatingsCacheEntry entry) async {
    final map = await _load();
    map[key] = entry;
    if (map.length > maxEntries) {
      // 超容淘汰最旧（评分缓存条目很小，400 条足够覆盖常用媒体库）。
      final sorted = map.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in sorted.take(map.length - maxEntries)) {
        map.remove(e.key);
      }
    }
    await _storage.write(
      key: _storageKey,
      value: jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }
}

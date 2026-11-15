import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 弹幕绑定来源：manual（用户手选）永久保存；auto（自动命中）30 天。
enum DanmakuMatchSource {
  auto('auto'),
  manual('manual');

  const DanmakuMatchSource(this.id);

  final String id;

  static DanmakuMatchSource fromId(String? id) =>
      DanmakuMatchSource.values.firstWhere(
        (e) => e.id == id,
        orElse: () => DanmakuMatchSource.auto,
      );
}

/// 一条绑定记忆：本地文件/条目 → 弹幕库 episodeId。
class DanmakuMatchRecord {
  const DanmakuMatchRecord({
    required this.episodeId,
    this.animeTitle = '',
    this.episodeTitle = '',
    this.source = DanmakuMatchSource.auto,
    this.savedAtMs = 0,
  });

  final int episodeId;
  final String animeTitle;
  final String episodeTitle;
  final DanmakuMatchSource source;
  final int savedAtMs;

  factory DanmakuMatchRecord.fromJson(Map<String, dynamic> json) =>
      DanmakuMatchRecord(
        episodeId: (json['episodeId'] as num?)?.toInt() ?? 0,
        animeTitle: json['animeTitle'] as String? ?? '',
        episodeTitle: json['episodeTitle'] as String? ?? '',
        source: DanmakuMatchSource.fromId(json['source'] as String?),
        savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'episodeId': episodeId,
        'animeTitle': animeTitle,
        'episodeTitle': episodeTitle,
        'source': source.id,
        'savedAtMs': savedAtMs,
      };

  DanmakuMatchRecord copyWith({int? savedAtMs}) => DanmakuMatchRecord(
        episodeId: episodeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        source: source,
        savedAtMs: savedAtMs ?? this.savedAtMs,
      );
}

/// 记忆条目（key + 记录），设置页管理列表用。
class DanmakuMatchEntry {
  const DanmakuMatchEntry({required this.key, required this.record});

  final String key;
  final DanmakuMatchRecord record;
}

/// 记忆键构造（纯函数）。
class DanmakuMatchKeys {
  const DanmakuMatchKeys._();

  /// 条目键：服务器 + 单集 itemId（换源/换服务器互不串）。
  static String item(String serverBaseUrl, String itemId) =>
      'srv:$serverBaseUrl|item:$itemId';

  /// 文件名键（兜底：itemId 变化后仍能按文件名命中）。
  static String name(String fileName) {
    final normalized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r'\.(mkv|mp4|avi|mov|ts|m2ts|webm|flv)$'),
          '',
        );
    return 'name:$normalized';
  }
}

/// 弹幕匹配记忆仓库（694 M2，借鉴 NeoPlayer「弹幕记忆」设计）。
///
/// 与 [DanmakuCache]（6h 进程内数据缓存）互补：这里是**绑定记忆**——
/// 「哪个文件/条目绑到哪个弹幕库 episodeId」，落盘持久，重启仍命中，
/// 冷启动可跳过整套 match/search。
///
/// TTL 策略（与 dandanplay「按 ID 缓存 2~6h」约定不冲突，那是数据缓存）：
/// - manual（用户手选绑定）：不过期，仅 LRU 淘汰；
/// - auto（自动命中）：30 天；命中后取弹幕失败/为空由调用方立即
///   [remove] 作废并回落自动匹配。
abstract class DanmakuMatchRepository {
  /// 查绑定（itemKey 优先，nameKey 兜底）；过期/不存在返回 null。
  Future<DanmakuMatchRecord?> get({String? itemKey, String? nameKey});

  /// 写绑定（两个键同写；LRU 淘汰最旧）。
  Future<void> put({
    String? itemKey,
    String? nameKey,
    required DanmakuMatchRecord record,
  });

  /// 删绑定（两键同删；命中失败作废用）。
  Future<void> remove({String? itemKey, String? nameKey});

  /// 全部条目（设置页管理列表，按最近保存倒序）。
  Future<List<DanmakuMatchEntry>> all();

  /// 清空全部绑定。
  Future<void> clear();
}

/// 本地持久化实现：`<应用文档目录>/himi_danmaku_matches.json`。
///
/// 文件结构 `{"version":1,"records":{"<key>":{...}}}`。按插入序 LRU
/// 淘汰，上限 [maxEntries]；损坏/不可读按空数据处理，不阻塞播放。
class LocalDanmakuMatchMemory implements DanmakuMatchRepository {
  LocalDanmakuMatchMemory({
    String? directory,
    DateTime Function()? now,
  })  : _directory = directory,
        _now = now ?? DateTime.now;

  final String? _directory;
  final DateTime Function() _now;

  static const String fileName = 'himi_danmaku_matches.json';
  static const int schemaVersion = 1;
  static const int maxEntries = 500;

  /// auto 绑定 TTL（30 天）。
  static const Duration autoTtl = Duration(days: 30);

  /// 写串行化锁（694 M4：多服务器并发命中时防 read-modify-write 竞态）。
  Future<void> _writeLock = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() op) {
    final next = _writeLock.then((_) => op());
    _writeLock = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _file() async {
    final dir = _directory ?? (await getApplicationDocumentsDirectory()).path;
    return File('$dir${Platform.pathSeparator}$fileName');
  }

  Future<Map<String, DanmakuMatchRecord>> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final records = decoded['records'];
      if (records is! Map) return {};
      return {
        for (final entry in records.entries)
          if (entry.value is Map)
            entry.key.toString(): DanmakuMatchRecord.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      }..removeWhere((_, r) => _expired(r));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, DanmakuMatchRecord> records) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'version': schemaVersion,
      'records': {
        for (final entry in records.entries) entry.key: entry.value.toJson(),
      },
    }));
  }

  /// 记录是否过期（manual 永不过期）。
  bool _expired(DanmakuMatchRecord r) =>
      r.source == DanmakuMatchSource.auto &&
      _now().difference(
            DateTime.fromMillisecondsSinceEpoch(r.savedAtMs),
          ) >
          autoTtl;

  @override
  Future<DanmakuMatchRecord?> get({String? itemKey, String? nameKey}) async {
    final records = await _load();
    for (final key in [itemKey, nameKey]) {
      if (key == null) continue;
      final record = records[key];
      if (record != null) return record;
    }
    return null;
  }

  @override
  Future<void> put({
    String? itemKey,
    String? nameKey,
    required DanmakuMatchRecord record,
  }) {
    return _synchronized(() async {
    final records = await _load();
    final saved = record.copyWith(savedAtMs: _now().millisecondsSinceEpoch);
    for (final key in [itemKey, nameKey]) {
      if (key == null || key.isEmpty) continue;
      records.remove(key); // 移到末尾 = 最近使用
      records[key] = saved;
    }
    while (records.length > maxEntries) {
      records.remove(records.keys.first);
    }
    await _save(records);
    });
  }

  @override
  Future<void> remove({String? itemKey, String? nameKey}) {
    return _synchronized(() async {
      final records = await _load();
      var dirty = false;
      for (final key in [itemKey, nameKey]) {
        if (key == null) continue;
        dirty = records.remove(key) != null || dirty;
      }
      if (dirty) await _save(records);
    });
  }

  @override
  Future<List<DanmakuMatchEntry>> all() async {
    final records = await _load();
    final entries = [
      for (final e in records.entries)
        DanmakuMatchEntry(key: e.key, record: e.value),
    ];
    entries.sort((a, b) => b.record.savedAtMs.compareTo(a.record.savedAtMs));
    return entries;
  }

  @override
  Future<void> clear() {
    return _synchronized(() async {
      final records = await _load();
      if (records.isEmpty) return;
      await _save({});
    });
  }
}

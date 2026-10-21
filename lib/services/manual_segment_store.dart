import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:himi_syncwatch/models/media_segment.dart';

/// 手动片头/片尾标记仓库。
///
/// 当前仅本地 JSON 实现；后续账号系统可增加远程实现并保持播放器调用不变。
abstract class ManualSegmentRepository {
  Future<ManualSegmentRecord?> get(String key);

  Future<ManualSegmentRecord> setIntroEnd({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int introEndMs,
  });

  Future<ManualSegmentRecord> setCreditsStart({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int creditsStartMs,
  });

  Future<void> clearIntro(String key);

  Future<void> clearCredits(String key);
}

/// 本地持久化实现：`<应用文档目录>/himi_manual_segments.json`。
///
/// 文件结构 `{"version":1,"records":{"<key>":{...}}}`。按 key LRU 淘汰，
/// 上限 [maxEntries]。文件损坏/不可读时按空数据处理，不阻塞播放。
class LocalManualSegmentStore implements ManualSegmentRepository {
  LocalManualSegmentStore({
    String? directory,
    DateTime Function()? now,
  })  : _directory = directory,
        _now = now ?? DateTime.now;

  final String? _directory;
  final DateTime Function() _now;

  static const String fileName = 'himi_manual_segments.json';
  static const int schemaVersion = 1;
  static const int maxEntries = 500;

  Future<File> _file() async {
    final dir = _directory ?? (await getApplicationDocumentsDirectory()).path;
    return File('$dir${Platform.pathSeparator}$fileName');
  }

  Future<Map<String, ManualSegmentRecord>> _load() async {
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
            entry.key.toString(): ManualSegmentRecord.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, ManualSegmentRecord> records) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'version': schemaVersion,
      'records': {
        for (final entry in records.entries) entry.key: entry.value.toJson(),
      },
    }));
  }

  @override
  Future<ManualSegmentRecord?> get(String key) async => (await _load())[key];

  @override
  Future<ManualSegmentRecord> setIntroEnd({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int introEndMs,
  }) async {
    return _upsert(
      key,
      serverId: serverId,
      seriesId: seriesId,
      itemId: itemId,
      providerIds: providerIds,
      introEndMs: introEndMs,
    );
  }

  @override
  Future<ManualSegmentRecord> setCreditsStart({
    required String key,
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    required int creditsStartMs,
  }) async {
    return _upsert(
      key,
      serverId: serverId,
      seriesId: seriesId,
      itemId: itemId,
      providerIds: providerIds,
      creditsStartMs: creditsStartMs,
    );
  }

  Future<ManualSegmentRecord> _upsert(
    String key, {
    required String serverId,
    String? seriesId,
    String? itemId,
    Map<String, String> providerIds = const {},
    int? introEndMs,
    int? creditsStartMs,
  }) async {
    final records = await _load();
    final old = records.remove(key);
    final now = _now().millisecondsSinceEpoch;
    final next = ManualSegmentRecord(
      serverId: serverId,
      seriesId: seriesId ?? old?.seriesId,
      itemId: itemId ?? old?.itemId,
      providerIds:
          providerIds.isNotEmpty ? providerIds : old?.providerIds ?? const {},
      introEndMs: introEndMs ?? old?.introEndMs,
      creditsStartMs: creditsStartMs ?? old?.creditsStartMs,
      updatedAtMs: now,
    );
    records[key] = next;
    while (records.length > maxEntries) {
      records.remove(records.keys.first);
    }
    await _save(records);
    return next;
  }

  @override
  Future<void> clearIntro(String key) => _clearField(key, intro: true);

  @override
  Future<void> clearCredits(String key) => _clearField(key, intro: false);

  Future<void> _clearField(String key, {required bool intro}) async {
    final records = await _load();
    final old = records[key];
    if (old == null) return;
    final next = old.copyWith(
      introEndMs: intro ? null : old.introEndMs,
      creditsStartMs: intro ? old.creditsStartMs : null,
      updatedAtMs: _now().millisecondsSinceEpoch,
    );
    if (!next.hasMarkers) {
      records.remove(key);
    } else {
      records[key] = next;
    }
    await _save(records);
  }
}

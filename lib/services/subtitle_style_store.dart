import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 单条字幕样式偏好（按 itemId 落盘；退出播放器重进同内容恢复）。
class SubtitleStylePrefs {
  const SubtitleStylePrefs({
    this.scale = 1.0,
    this.marginY = 22,
    this.delayMs = 0,
  });

  /// 字幕缩放（mdk `subtitle.scale`，1.0 = 原始）。
  final double scale;

  /// 字幕底部边距 px（mdk `subtitle.margin.y`）。
  final int marginY;

  /// 字幕延迟毫秒（正 = 晚显示，负 = 提前）。
  final int delayMs;

  /// 与 mdk 默认属性一致即「默认」。
  bool get isDefault => scale == 1.0 && marginY == 22 && delayMs == 0;

  SubtitleStylePrefs copyWith({double? scale, int? marginY, int? delayMs}) {
    return SubtitleStylePrefs(
      scale: scale ?? this.scale,
      marginY: marginY ?? this.marginY,
      delayMs: delayMs ?? this.delayMs,
    );
  }

  Map<String, dynamic> toJson() =>
      {'scale': scale, 'marginY': marginY, 'delayMs': delayMs};

  factory SubtitleStylePrefs.fromJson(Map<String, dynamic> json) {
    return SubtitleStylePrefs(
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      marginY: (json['marginY'] as num?)?.toInt() ?? 22,
      delayMs: (json['delayMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleStylePrefs &&
      other.scale == scale &&
      other.marginY == marginY &&
      other.delayMs == delayMs;

  @override
  int get hashCode => Object.hash(scale, marginY, delayMs);
}

/// 按内容 id 持久化的字幕样式存储（JSON 文件）。
///
/// 文件：`<应用文档目录>/himi_subtitle_styles.json`，结构
/// `{"<itemId>": {scale, marginY, delayMs}, …}`。容量上限 [maxEntries]，
/// 超限按插入顺序淘汰最旧（重插 = LRU 触达）。写入由播放页去抖，
/// 单实例串行调用即可，无需锁。
class SubtitleStyleStore {
  SubtitleStyleStore({String? directory}) : _directory = directory;

  /// 注入目录（测试用临时目录；null = 运行时取应用文档目录）。
  final String? _directory;

  static const String fileName = 'himi_subtitle_styles.json';
  static const int maxEntries = 100;

  Future<File> _file() async {
    final dir = _directory ?? (await getApplicationDocumentsDirectory()).path;
    return File('$dir${Platform.pathSeparator}$fileName');
  }

  Future<Map<String, SubtitleStylePrefs>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is Map<String, dynamic>)
            e.key: SubtitleStylePrefs.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      // 文件损坏/不可读：按无记录处理，不阻塞播放
      return {};
    }
  }

  Future<SubtitleStylePrefs?> get(String key) async => (await load())[key];

  Future<void> put(String key, SubtitleStylePrefs prefs) async {
    final map = await load();
    map.remove(key);
    map[key] = prefs; // 重插到末尾 = LRU 触达
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
    final f = await _file();
    await f.writeAsString(
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }
}

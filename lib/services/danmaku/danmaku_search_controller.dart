import 'package:flutter/foundation.dart';

import 'dandanplay_client.dart';
import 'danmaku_matcher.dart';
import 'danmaku_caches.dart';
import 'danmaku_match_memory.dart';

/// 弹幕搜索/绑定控制器（694 M3 核心）。
///
/// 三壳（Flutter sheet / Windows QML 面板 / Android TV 原生面板）共用的
/// 纯逻辑状态机：**搜索、绑定、记忆写入全在这里**，UI 壳只做输入输出
/// （Qt/安卓壳由适配层把 [revision] 转成状态推送）。
///
/// 绑定语义：绑定 = 写入 [DanmakuMatchRepository]（manual 永久），
/// 随后由调用方触发 `_loadDanmaku(force: true)`——现有加载管线的
/// 「记忆优先」路径会直接命中，无需另起取弹幕通道。
class DanmakuSearchController {
  DanmakuSearchController({
    required DandanplayClient client,
    required String itemKey,
    required String nameKey,
    this.fileName = '',
    this.episodeNumber = 0,
    DanmakuMatchRepository? memory,
  })  : _client = client,
        _itemKey = itemKey,
        _nameKey = nameKey,
        _memory = memory ?? DanmakuCaches.matchMemory;

  final DandanplayClient _client;
  final String _itemKey;
  final String _nameKey;
  final DanmakuMatchRepository _memory;

  /// 本地文件名（match API 扩搜用，可空）。
  final String fileName;

  /// 当前集号（>0 时首选 `episode=` 服务端按集过滤，命中即本集）。
  final int episodeNumber;

  /// 当前绑定（null = 未匹配/未绑定）。
  DanmakuMatchRecord? binding;

  /// 搜索结果（空 = 未搜索或无结果）。
  List<MatchCandidate> results = const [];

  /// 搜索进行中（壳显示 loading）。
  bool searching = false;

  /// 最近错误提示（null = 无）。
  String? error;

  /// 变更通知（壳订阅后重建 UI）。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _notify() => revision.value++;

  /// 绑定状态文案（面板状态行用）。
  String get bindingLabel {
    final b = binding;
    if (b == null) return '未匹配';
    final source = b.source == DanmakuMatchSource.manual ? '手动' : '自动';
    final title = b.animeTitle.isNotEmpty ? b.animeTitle : 'episodeId ${b.episodeId}';
    final ep = b.episodeTitle.isNotEmpty ? ' · ${b.episodeTitle}' : '';
    return '$title$ep（$source）';
  }

  /// 打开面板时初始化：读当前绑定。
  Future<void> load() async {
    binding = await _memory.get(itemKey: _itemKey, nameKey: _nameKey);
    _notify();
  }

  /// 按关键词搜索（空关键词直接报错提示）。
  ///
  /// 694：**模糊搜索扩大范围**——多关键词变体 + `match(fileName)` 并发
  /// 扩搜，按 episodeId 去重合并（早变体命中在前）。四壳（Flutter /
  /// Qt / 安卓 / 鸿蒙）搜索逻辑同源，此处置宽即全平台生效。
  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      error = '请输入搜索关键词';
      _notify();
      return;
    }
    // N5（694，借鉴 NeoPlayer「搜索标题无效或属于协议前缀」）：
    // URL/协议前缀不是标题，直接拦。
    if (_looksLikeUrl(kw)) {
      error = '搜索标题无效或属于协议前缀';
      _notify();
      return;
    }
    searching = true;
    error = null;
    _notify();
    try {
      var failed = 0;
      final variants = _searchVariants(kw);
      final futures = <Future<List<MatchCandidate>>>[
        // N1：带集号的过滤查询置前——命中即本集，合并时排最前。
        if (episodeNumber > 0)
          _safeSearch(kw, episode: episodeNumber).catchError((_) {
            failed++;
            return const <MatchCandidate>[];
          }),
        for (final v in variants)
          _safeSearch(v).catchError((_) {
            failed++;
            return const <MatchCandidate>[];
          }),
        if (fileName.trim().isNotEmpty)
          _safeMatch(fileName).catchError((_) {
            failed++;
            return <MatchCandidate>[];
          }),
      ];
      final lists = await Future.wait(futures);
      final seen = <int>{};
      final merged = <MatchCandidate>[];
      for (final list in lists) {
        for (final c in list) {
          if (seen.add(c.episodeId)) merged.add(c);
        }
      }
      results = merged;
      if (results.isEmpty) {
        // 全部查询都抛异常 = 搜索失败；有成功但无命中 = 未找到。
        error = failed >= futures.length
            ? '弹幕搜索失败'
            : '未找到弹幕，换个关键词试试';
      }
    } catch (e) {
      results = const [];
      error = '弹幕搜索失败：$e';
    } finally {
      searching = false;
      _notify();
    }
  }

  /// 搜索词变体（模糊扩搜）：原词 → 清洗词 → 放宽核心词。
  List<String> _searchVariants(String kw) {
    final out = <String>[kw];
    final cleaned = DanmakuMatcher.cleanTitle(kw);
    if (cleaned.isNotEmpty && !out.contains(cleaned)) out.add(cleaned);
    final core = _coreVariant(cleaned.isNotEmpty ? cleaned : kw);
    if (core.isNotEmpty && !out.contains(core)) out.add(core);
    return out;
  }

  /// 放宽核心词：≥2 词丢末词（尾词多为限定词/季标记，如「第二季」）；
  /// 无空格长标题取前 6 字（提高召回）。
  static String _coreVariant(String s) {
    final parts =
        s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return parts.sublist(0, parts.length - 1).join(' ');
    if (parts.length <= 1 && s.length > 6) return s.substring(0, 6);
    return '';
  }

  /// N5：URL/协议前缀识别（含 www. 开头）。
  static bool _looksLikeUrl(String s) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(s) ||
      s.toLowerCase().startsWith('www.');

  // 注意：_safeSearch/_safeMatch **不内部吞异常**——失败计数靠外层
  // catchError（区分「全部失败=搜索失败」与「有成功无命中=未找到」）。
  Future<List<MatchCandidate>> _safeSearch(String kw, {int? episode}) =>
      _client.searchEpisodes(kw, episode: episode);

  Future<List<MatchCandidate>> _safeMatch(String name) =>
      _client.match(fileName: name);

  /// 绑定候选（manual 永久记忆）；调用方随后触发弹幕重载。
  Future<DanmakuMatchRecord> bind(MatchCandidate candidate) async {
    final record = DanmakuMatchRecord(
      episodeId: candidate.episodeId,
      animeTitle: candidate.animeTitle,
      episodeTitle: candidate.episodeTitle,
      source: DanmakuMatchSource.manual,
    );
    await _memory.put(itemKey: _itemKey, nameKey: _nameKey, record: record);
    binding = record;
    error = null;
    _notify();
    return record;
  }

  /// 解绑（回到自动匹配）；调用方随后触发弹幕重载。
  Future<void> unbind() async {
    await _memory.remove(itemKey: _itemKey, nameKey: _nameKey);
    binding = null;
    _notify();
  }

  /// 释放（壳销毁时调用）。
  void dispose() {
    revision.dispose();
  }
}

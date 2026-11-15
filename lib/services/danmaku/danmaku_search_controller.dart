import 'package:flutter/foundation.dart';

import 'dandanplay_client.dart';
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
    DanmakuMatchRepository? memory,
  })  : _client = client,
        _itemKey = itemKey,
        _nameKey = nameKey,
        _memory = memory ?? DanmakuCaches.matchMemory;

  final DandanplayClient _client;
  final String _itemKey;
  final String _nameKey;
  final DanmakuMatchRepository _memory;

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
  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      error = '请输入搜索关键词';
      _notify();
      return;
    }
    searching = true;
    error = null;
    _notify();
    try {
      results = await _client.searchEpisodes(kw);
      if (results.isEmpty) error = '未找到弹幕，换个关键词试试';
    } catch (e) {
      results = const [];
      error = '弹幕搜索失败：$e';
    } finally {
      searching = false;
      _notify();
    }
  }

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

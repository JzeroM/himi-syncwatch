import 'danmaku_cache.dart';
import 'danmaku_comment.dart';
import 'danmaku_match_memory.dart';

class DanmakuCaches {
  DanmakuCaches._();

  static final DanmakuCache<int> episode = DanmakuCache<int>();
  static final DanmakuCache<List<DanmakuComment>> comments =
      DanmakuCache<List<DanmakuComment>>();

  /// 匹配记忆（694 M2，落盘持久；测试可整体替换）。
  static DanmakuMatchRepository matchMemory = LocalDanmakuMatchMemory();

  static int get totalCount {
    var count = 0;
    for (final cached in comments.values) {
      count += cached.length;
    }
    return count;
  }

  /// 清进程内缓存。**不含 [matchMemory]**（绑定记忆是用户数据）。
  static void clear() {
    episode.clear();
    comments.clear();
  }
}

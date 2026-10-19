import 'danmaku_cache.dart';
import 'danmaku_comment.dart';

class DanmakuCaches {
  DanmakuCaches._();

  static final DanmakuCache<int> episode = DanmakuCache<int>();
  static final DanmakuCache<List<DanmakuComment>> comments =
      DanmakuCache<List<DanmakuComment>>();

  static int get totalCount {
    var count = 0;
    for (final cached in comments.values) {
      count += cached.length;
    }
    return count;
  }

  static void clear() {
    episode.clear();
    comments.clear();
  }
}

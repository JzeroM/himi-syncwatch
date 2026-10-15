import 'package:himi_syncwatch/models/media_counts.dart';

/// 资源统计：不含多版本 / 包含多版本 × 电影/剧集/集。
class LibraryCounts {
  const LibraryCounts({this.withoutVersions, this.withVersions});

  /// 不含多版本（/Items/Counts?UserId=，与首页卡片同口径）。
  final MediaCounts? withoutVersions;

  /// 包含多版本（/Items 无 UserId，服务器全库口径）。
  final MediaCounts? withVersions;

  bool get isEmpty => withoutVersions == null && withVersions == null;

  @override
  String toString() =>
      'LibraryCounts(without: $withoutVersions, with: $withVersions)';
}

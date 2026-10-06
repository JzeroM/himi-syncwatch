import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 续播数据修订号：播放停止上报成功、标记已观看等「会影响 Emby 续播列表」
/// 的操作后 +1 → 首页「继续观看」栏据此即时重取，保证实时性。
final resumeRevisionProvider = StateProvider<int>((ref) => 0);

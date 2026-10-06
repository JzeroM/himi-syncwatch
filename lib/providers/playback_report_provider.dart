import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 续播数据修订号：播放停止上报成功、标记已观看等「会影响 Emby 续播列表」
/// 的操作后 +1 → 首页「继续观看」栏据此即时重取，保证实时性。
final resumeRevisionProvider = StateProvider<int>((ref) => 0);

/// 「乐观隐藏」的续播条目 id 集合：点「重播」时立即加入（首页立刻从
/// 继续观看栏移除该条），待播放器上报成功（服务器真相回来）或详情页返回时
/// 移除，交回服务器数据驱动显示。
final resumeOptimisticHiddenProvider = StateProvider<Set<String>>((ref) => {});

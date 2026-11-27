import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 房主创建房间时，暂存选中的剧集列表（通过 Riverpod 在页面间传递，避免 URL 编码问题）
final pendingRoomEpisodesProvider =
    StateProvider<List<Map<String, dynamic>>?>((ref) => null);

/// 房主创建房间时，暂存选中的电影数据
final pendingRoomMovieProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

/// 698 N72：当前播放资源 id（Qt 双窗口单人态消费——同资源详情按钮禁用）。
/// 播放器起播写入、停止/退出清 null。
final currentPlayingItemIdProvider = StateProvider<String?>((ref) => null);

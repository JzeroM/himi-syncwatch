import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 房主创建房间时，暂存选中的剧集列表（通过 Riverpod 在页面间传递，避免 URL 编码问题）
final pendingRoomEpisodesProvider =
    StateProvider<List<Map<String, dynamic>>?>((ref) => null);

/// 房主创建房间时，暂存选中的电影数据
final pendingRoomMovieProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/screens/player/player_orientation.dart';

/// 房间资源搜索入口：竖屏窗口覆盖整个搜索过程。
///
/// - 进入强制竖屏（搜索页与其上的 roomMode 详情全程竖屏）
/// - `await` 结束（资源带回或用户返回面板）后恢复沉浸横屏
/// - 返回资源数据 `Map`；用户未选资源直接返回为 null
/// - 恢复横屏固定 left 侧，与资源面板原 showSearch 版行为一致
Future<Map<String, dynamic>?> pushRoomResourceSearch(
  BuildContext context, {
  required String roomCode,
}) async {
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final data = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => GlobalSearchScreen(roomCode: roomCode),
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await requestPlayerLandscape(PlayerLandscapeSide.left);
  return data;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每服务器头像版本号：上传头像/重新登录成功后自增，触发服务器卡片与
/// 服务设置面板头像刷新（URL 追加 `?_v=<n>` 绕过图片缓存）。
class ServerAvatarVersionNotifier extends StateNotifier<Map<String, int>> {
  ServerAvatarVersionNotifier() : super(const {});

  void bump(String serverId) {
    state = {...state, serverId: (state[serverId] ?? 0) + 1};
  }
}

final serverAvatarVersionProvider =
    StateNotifierProvider<ServerAvatarVersionNotifier, Map<String, int>>(
  (ref) => ServerAvatarVersionNotifier(),
);

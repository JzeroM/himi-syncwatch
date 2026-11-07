import 'dart:io';

import 'package:himi_syncwatch/services/rtm/agora_rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/ohos_rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/unsupported_rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/windows_rtm_backend.dart';

/// 按平台选择 RTM 后端：
/// - Windows: himi_windows_rtm 插件（agora_rtm 无 Windows 原生实现）
/// - 鸿蒙: himi_ohos_rtm 插件（声网 RTM **NAPI 直连**，见下方注释）
/// - macOS / Linux: 快速失败降级（agora_rtm 同样无原生实现）
/// - Android / iOS: agora_rtm 插件
RtmBackend createRtmBackend() {
  if (Platform.isWindows) {
    return WindowsRtmBackend();
  }
  // 鸿蒙：直接用声网原生库 `libagora-rtm-sdk.so`（标准 NAPI 模块），
  // 不走 `@shengwang/rtm-full` bytecode HAR。
  //
  // 为什么不能用 bytecode HAR：它强制 `useNormalizedOHMUrl: true`，而该
  // 开关是项目级的，会破坏 Flutter-OH 的 entry 模块解析（entryPath 是
  // 目录 `src/main/`，精确模式下找不到 EntryAbility）→ 启动即闪退：
  //   Cannot find module 'ets/entryability/EntryAbility',
  //   which is application Entry Point
  // 底层 `.so` 自包含全部 49 个 API（nm_modname = "agora-rtm-sdk"），
  // 因此可以像 mpv 插件那样直接 import，仍是声网官方 SDK 与服务器。
  if (Platform.operatingSystem == 'ohos') {
    return OhosRtmBackend();
  }
  if (Platform.isMacOS || Platform.isLinux) {
    return UnsupportedRtmBackend();
  }
  return AgoraRtmBackend();
}

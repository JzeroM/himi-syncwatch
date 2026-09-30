import 'dart:io';

import 'package:himi_syncwatch/services/rtm/agora_rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/unsupported_rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm/windows_rtm_backend.dart';

/// 按平台选择 RTM 后端：
/// - Windows: himi_windows_rtm 插件（agora_rtm 无 Windows 原生实现）
/// - macOS / Linux: 快速失败降级（agora_rtm 同样无原生实现）
/// - Android / iOS: agora_rtm 插件
RtmBackend createRtmBackend() {
  if (Platform.isWindows) {
    return WindowsRtmBackend();
  }
  if (Platform.isMacOS || Platform.isLinux) {
    return UnsupportedRtmBackend();
  }
  return AgoraRtmBackend();
}

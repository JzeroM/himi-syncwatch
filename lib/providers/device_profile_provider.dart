import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/services/device_profile.dart';

/// 启动设备能力评估结果（`_bootstrap` 探测后 overrideWith 注入）。
///
/// 默认 [DeviceProfile.unknown]（未探测）：路由按保守/历史行为兜底，
/// 既有 widget 测试无需覆写即可运行；「播放器配置」页卡片按钮可
/// `ref.read(deviceProfileProvider.notifier).state = ...` 重新评估。
final deviceProfileProvider =
    StateProvider<DeviceProfile>((ref) => DeviceProfile.unknown);

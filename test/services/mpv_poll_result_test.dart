import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart';

void main() {
  test('MpvPollResult 解析 HarmonyOS Vulkan 诊断字段', () {
    final result = MpvPollResult.fromMap(<Object?, Object?>{
      'durationMs': 1234,
      'positionMs': 567,
      'bufferedMs': 89,
      'paused': false,
      'eofReached': false,
      'idleActive': false,
      'playlistCount': 1,
      'pausedForCache': false,
      'cachePercent': 100.0,
      'hwdecCurrent': 'ohcodec',
      'gpuContext': 'ohosvk',
      'currentVo': 'gpu-next',
    });

    expect(result.hwdecCurrent, 'ohcodec');
    expect(result.gpuContext, 'ohosvk');
    expect(result.currentVo, 'gpu-next');
  });
}

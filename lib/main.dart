import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:himi_syncwatch/core/app.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_windows_rtm/himi_windows_rtm.dart';
import 'package:window_manager/window_manager.dart';

/// RTM 冒烟自检（CI/故障排查用）：设置环境变量 HIMI_RTM_SMOKE=1 后启动，
/// 直连插件跑 initialize → login → subscribe → publish → release，
/// 进度实时写入 LogService（himi_runtime.log 闪退后可取证），退出码 0=通过。
Future<int> _runRtmSmoke() async {
  final env = Platform.environment;
  const fallbackAppId = '0123456789abcdef0123456789abcdef';
  final appId = env['HIMI_RTM_SMOKE_APP_ID'] ?? fallbackAppId;
  var stepNo = 0;
  void step(String msg) {
    stepNo++;
    LogService().log('SMOKE', '[$stepNo] $msg');
    // ignore: avoid_print
    stdout.writeln('[SMOKE][$stepNo] $msg');
  }

  try {
    final userId = 'smoke${DateTime.now().millisecondsSinceEpoch % 1000000}';
    step('initialize start userId=$userId appId=$appId');
    final initOk =
        await WindowsRtmClient.initialize(appId: appId, userId: userId);
    step('initialize ok=$initOk');
    if (!initOk) return 2;

    step('login start');
    final loginResult = await WindowsRtmClient.invokeForResult(
        'login', {'token': ''});
    step('login ok=${loginResult['ok']} reason=${loginResult['reason']}');
    final loginOk = loginResult['ok'] == true;

    step('subscribe start');
    final subResult =
        await WindowsRtmClient.invokeForResult('subscribe', {'channel': 'smoke_channel'});
    step('subscribe ok=${subResult['ok']} reason=${subResult['reason']}');

    // 在线人数查询链路（rid/回调/解析）。仅在真实 AppId 登录成功时硬断言；
    // CI 未配 HIMI_RTM_SMOKE_APP_ID 时 login 会 Invalid App id，此环境只验不崩。
    step('getOnlineUsers start');
    int? onlineCount;
    for (var i = 0; i < 5; i++) {
      final usersResult = await WindowsRtmClient.invokeForResult(
          'getOnlineUsers', {'channel': 'smoke_channel'});
      onlineCount = usersResult['count'] is int
          ? usersResult['count'] as int
          : null;
      step('getOnlineUsers try=${i + 1} ok=${usersResult['ok']} '
          'reason=${usersResult['reason']} count=$onlineCount');
      if (usersResult['ok'] == true && onlineCount != null && onlineCount >= 1) {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (loginOk) {
      if (onlineCount == null || onlineCount < 1) {
        step('getOnlineUsers ASSERT FAILED (count=$onlineCount)');
        return 3;
      }
    } else {
      step('login 未成功(未配置真实 AppId?), 跳过 getOnlineUsers 硬断言');
    }

    step('publish start');
    final pubOk = await WindowsRtmClient.publish('smoke_channel',
        '{"type":"smoke","ts":${DateTime.now().millisecondsSinceEpoch}}');
    step('publish ok=$pubOk');

    // 覆盖 SDK 首轮网络回调/心跳窗口（悬垂类崩溃多在数秒内触发）
    step('wait 20s for async callbacks/heartbeats');
    await Future<void>.delayed(const Duration(seconds: 20));

    step('release start');
    await WindowsRtmClient.release();
    step('release done');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    step('SMOKE PASS');
    return 0;
  } catch (e, st) {
    step('EXCEPTION: $e\n$st');
    return 1;
  }
}

class _SelfSignedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows &&
      Platform.environment.containsKey('HIMI_RTM_SMOKE')) {
    final smokeCode = await _runRtmSmoke();
    exit(smokeCode);
  }
  // 桌面三端：窗口管理（播放器窗口全屏）依赖
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
    } catch (_) {}
  }
  HttpOverrides.global = _SelfSignedHttpOverrides();
  fvp.registerWith();

  final authService = EmbyAuthService();
  await authService.init();

  final agoraNotifier = AgoraConfigNotifier();
  await agoraNotifier.load();

  final settingsNotifier = SettingsNotifier();
  await settingsNotifier.load();

  runApp(
    ProviderScope(
      overrides: [
        embyAuthServiceProvider.overrideWithValue(authService),
        agoraConfigProvider.overrideWith((ref) => agoraNotifier),
        settingsProvider.overrideWith((ref) => settingsNotifier),
      ],
      child: const HimiSyncApp(),
    ),
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙 RTM 接入的**源码级**校验。
///
/// 单元测试无法真连声网（需 App ID + 真机），故这里验证：
/// ① SDK 集成配置正确（依赖 / 权限 / bytecode HAR 开关）；
/// ② 插件与 Dart 后端的方法/事件协议一致；
/// ③ 工厂正确路由到鸿蒙后端；
/// ④ 关键 SDK API 用法与实测签名匹配（避免编译期才发现）。
void main() {
  final buildProfile =
      File('ohos/build-profile.json5').readAsStringSync();
  final entryPackage =
      File('ohos/entry/oh-package.json5').readAsStringSync();
  final moduleJson =
      File('ohos/entry/src/main/module.json5').readAsStringSync();
  final factory = File(
    'lib/services/rtm/rtm_backend_factory.dart',
  ).readAsStringSync();
  final backend = File(
    'lib/services/rtm/ohos_rtm_backend.dart',
  ).readAsStringSync();
  final dartClient = File(
    'plugins/himi_ohos_rtm/lib/himi_ohos_rtm.dart',
  ).readAsStringSync();
  final arktsManager = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/RtmManager.ets',
  ).readAsStringSync();
  final arktsPlugin = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/HimiOhosRtmPlugin.ets',
  ).readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('① SDK 集成配置', () {
    test('.har 已入库', () {
      expect(
        File('ohos/entry/har/AgoraRtmSDK.har').existsSync(),
        isTrue,
        reason: '声网 .har 必须提交到仓库（5.2MB）',
      );
    });

    test('entry 声明 @shengwang/rtm-full 依赖', () {
      expect(entryPackage, contains('@shengwang/rtm-full'));
      expect(entryPackage, contains('har/AgoraRtmSDK.har'));
    });

    test('bytecode HAR 必须开 useNormalizedOHMUrl（buildOption.strictMode）', () {
      // 第一轮验证踩坑：不开会报
      //   Bytecode HARs: [...] not supported when useNormalizedOHMUrl is not true.
      expect(buildProfile, contains('"useNormalizedOHMUrl": true'));
      // 第二轮验证踩坑：放 products 顶层会 schema 校验失败。
      expect(buildProfile, contains('"buildOption"'));
      expect(buildProfile, contains('"strictMode"'));
    });

    test('网络权限齐全（INTERNET + GET_NETWORK_INFO）', () {
      expect(moduleJson, contains('ohos.permission.INTERNET'));
      expect(moduleJson, contains('ohos.permission.GET_NETWORK_INFO'));
    });

    test('插件已加入 pubspec', () {
      expect(pubspec, contains('himi_ohos_rtm'));
      expect(pubspec, contains('plugins/himi_ohos_rtm'));
    });
  });

  group('② 插件与 Dart 后端的协议一致性', () {
    const methods = [
      'initialize',
      'login',
      'logout',
      'subscribe',
      'unsubscribe',
      'publish',
      'getOnlineUsers',
      'setChannelMetadata',
      'getChannelMetadata',
      'release',
    ];

    test('MethodChannel 名一致', () {
      expect(dartClient, contains("MethodChannel('himi_ohos_rtm')"));
      expect(arktsPlugin, contains("'himi_ohos_rtm'"));
    });

    test('EventChannel 名一致', () {
      expect(dartClient, contains("EventChannel('himi_ohos_rtm/events')"));
      expect(arktsPlugin, contains("'himi_ohos_rtm/events'"));
    });

    test('10 个方法两侧都有', () {
      for (final m in methods) {
        expect(arktsPlugin, contains("case '$m':"), reason: 'ArkTS 缺 $m');
        expect(dartClient, contains("'$m'"), reason: 'Dart 缺 $m');
      }
    });
  });

  group('③ 工厂路由', () {
    test('ohos 返回 OhosRtmBackend（不再 Unsupported）', () {
      expect(factory, contains("Platform.operatingSystem == 'ohos'"));
      expect(factory, contains('OhosRtmBackend()'));
      // 旧实现把 ohos 归入不支持平台。
      expect(
        factory,
        isNot(contains("Platform.isLinux ||\n      Platform.operatingSystem == 'ohos'")),
      );
    });

    test('macOS / Linux 仍降级', () {
      expect(factory, contains('UnsupportedRtmBackend()'));
      expect(factory, contains('Platform.isMacOS || Platform.isLinux'));
    });
  });

  group('④ SDK API 用法与实测签名匹配', () {
    test('presence 事件类型映射（join=3 / leave=4 / timeout=5）', () {
      final body = arktsManager.substring(
        arktsManager.indexOf('private mapPresenceType'),
      );
      expect(body, contains('t === 3'));
      expect(body, contains("return 'join'"));
      expect(body, contains('t === 4'));
      expect(body, contains("return 'leave'"));
      expect(body, contains('t === 5'));
      expect(body, contains("return 'timeout'"));
    });

    test('Dart 侧字符串 → 枚举映射', () {
      expect(backend, contains("'join' => RtmPresenceEventType.remoteJoinChannel"));
      expect(
        backend,
        contains("'leave' => RtmPresenceEventType.remoteLeaveChannel"),
      );
      expect(backend, contains("'timeout' => RtmPresenceEventType.remoteTimeout"));
    });

    test('getChannelMetadata 用 resp.data（不是 metadata）', () {
      // 实测：GetChannelMetadataResponse 字段名是 data。
      expect(arktsManager, contains('const data: Metadata = resp.data;'));
      expect(arktsManager, contains('const items: MetadataItem[] = data.items;'));
    });

    test('setChannelMetadata 不回读 revision（响应无该字段）', () {
      // 实测：SetChannelMetadataResponse 只有 channelName/channelType。
      expect(arktsManager, isNot(contains('resp.metadata')));
    });

    test('whoNow 参数与返回字段正确', () {
      expect(arktsManager, contains('c.presence.whoNow('));
      expect(arktsManager, contains('RtmChannelType.MESSAGE'));
      expect(arktsManager, contains('totalOccupancy'));
      expect(arktsManager, contains('userStateList'));
    });

    test('subscribe 传 withMessage + withPresence', () {
      expect(arktsManager, contains('withMessage: true'));
      expect(arktsManager, contains('withPresence: true'));
    });

    test('publish 传 channelType: MESSAGE', () {
      expect(arktsManager, contains('RtmChannelType.MESSAGE'));
      expect(arktsManager, contains('customType'));
    });
  });

  group('⑤ 后端行为对齐 Windows（竞态防御等）', () {
    test('订阅失败 500ms 重试一次', () {
      expect(backend, contains('Duration(milliseconds: 500)'));
      expect(backend, contains('订阅失败'));
    });

    test('查询失败保留上次值（不清零）', () {
      expect(backend, contains('_lastOnlineCount'));
      expect(backend, contains('_lastOnlineIds'));
    });

    test('dispose 释放事件订阅与流', () {
      final body = backend.substring(backend.indexOf('Future<void> dispose()'));
      expect(body, contains('_eventSubscription?.cancel()'));
      expect(body, contains('HimiOhosRtmClient.release()'));
      expect(body, contains('_messageController.close()'));
      expect(body, contains('_presenceController.close()'));
    });
  });
}

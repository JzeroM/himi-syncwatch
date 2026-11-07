import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 鸿蒙 RTM 接入的**源码级**校验（NAPI 直连方案）。
///
/// 单元测试无法真连声网（需 App ID + 真机），故这里验证：
/// ① NAPI 集成配置正确（.so / 类型声明 / 依赖，且**不含** bytecode HAR）；
/// ② 插件与 Dart 后端的方法/事件协议一致；
/// ③ 工厂正确路由到鸿蒙后端；
/// ④ 关键 NAPI API 用法与实测签名匹配（避免编译期才发现）。
///
/// 为什么强调「不含 bytecode HAR」：
/// `@shengwang/rtm-full` 是 bytecode HAR，强制 `useNormalizedOHMUrl: true`，
/// 而该开关破坏 Flutter-OH 的 entry 解析 → 真机启动闪退（628 事故）。
/// 本测试把这条约束锁死，防止后续误加回依赖。
/// 去掉 json5 的行注释，避免「注释里提到 @shengwang/rtm-full」被误判成依赖。
String stripLineComments(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i >= 0 ? line.substring(0, i) : line;
    })
    .join('\n');

void main() {
  final buildProfile =
      File('ohos/build-profile.json5').readAsStringSync();
  final buildProfileCode = stripLineComments(buildProfile);
  final entryPackage =
      File('ohos/entry/oh-package.json5').readAsStringSync();
  final entryPackageCode = stripLineComments(entryPackage);
  final pluginPackage = File(
    'plugins/himi_ohos_rtm/ohos/oh-package.json5',
  ).readAsStringSync();
  final pluginPackageCode = stripLineComments(pluginPackage);
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

  group('① NAPI 集成配置', () {
    test('原生库 .so 已入库（libagora-rtm-sdk + libaosl）', () {
      expect(
        File('plugins/himi_ohos_rtm/ohos/libs/arm64-v8a/libagora-rtm-sdk.so')
            .existsSync(),
        isTrue,
        reason: 'NAPI 直连的核心：声网原生库必须在插件 libs/ 下',
      );
      expect(
        File('plugins/himi_ohos_rtm/ohos/libs/arm64-v8a/libaosl.so')
            .existsSync(),
        isTrue,
        reason: 'libagora-rtm-sdk.so 的 NEEDED 依赖，缺了会加载失败',
      );
    });

    test('NAPI 类型声明已入库（index.d.ts + oh-package.json5）', () {
      final dts = File(
        'plugins/himi_ohos_rtm/ohos/src/main/cpp/types/libagora-rtm-sdk/index.d.ts',
      );
      expect(dts.existsSync(), isTrue);
      final content = dts.readAsStringSync();
      // 关键导出必须存在，否则 ArkTS 编译期就会报 undefined。
      for (final fn in [
        'createRtmClient',
        'releaseRtmClient',
        'login',
        'logout',
        'subscribe',
        'unsubscribe',
        'publish',
        'addEventListener',
        'whoNow',
        'setChannelMetadata',
        'getChannelMetadata',
        'getVersion',
      ]) {
        expect(content, contains('export const $fn'),
            reason: 'index.d.ts 缺 $fn');
      }
      expect(
        File(
          'plugins/himi_ohos_rtm/ohos/src/main/cpp/types/libagora-rtm-sdk/oh-package.json5',
        ).existsSync(),
        isTrue,
        reason: '类型包必须有 oh-package.json5，否则 ohpm 不认',
      );
    });

    test('插件依赖 NAPI 类型包，且不含 bytecode HAR', () {
      expect(pluginPackageCode, contains('libagora-rtm-sdk.so'));
      expect(pluginPackageCode, contains('src/main/cpp/types/libagora-rtm-sdk'));
      // 关键回归锁：绝不能依赖 @shengwang/rtm-full（bytecode HAR）。
      expect(
        pluginPackageCode,
        isNot(contains('@shengwang/rtm-full')),
        reason: 'bytecode HAR 会强制 useNormalizedOHMUrl → 启动闪退',
      );
    });

    test('entry 不含 bytecode HAR 依赖', () {
      expect(
        entryPackageCode,
        isNot(contains('@shengwang/rtm-full')),
        reason: 'entry 若依赖 bytecode HAR，hvigor 会强制开开关',
      );
      expect(entryPackageCode, isNot(contains('AgoraRtmSDK.har')));
    });

    test('useNormalizedOHMUrl 必须为 false（防启动闪退）', () {
      // 真机日志实证（628 事故）：
      //   Cannot find module 'ets/entryability/EntryAbility',
      //   which is application Entry Point
      expect(
        buildProfileCode,
        contains('"useNormalizedOHMUrl": false'),
        reason: '该开关会破坏 Flutter-OH 的 entry 模块解析',
      );
      expect(
        buildProfileCode,
        isNot(contains('"useNormalizedOHMUrl": true')),
        reason: '绝不能开，否则鸿蒙版启动即闪退',
      );
      // 字段位置仍需在 products[].buildOption.strictMode（放顶层 schema 拒绝）。
      expect(buildProfileCode, contains('"buildOption"'));
      expect(buildProfileCode, contains('"strictMode"'));
    });

    test('网络权限齐全（INTERNET + GET_NETWORK_INFO）', () {
      expect(moduleJson, contains('ohos.permission.INTERNET'));
      expect(moduleJson, contains('ohos.permission.GET_NETWORK_INFO'));
    });

    test('插件已加入 pubspec', () {
      expect(pubspec, contains('himi_ohos_rtm'));
      expect(pubspec, contains('plugins/himi_ohos_rtm'));
    });

    test('ArkTS 侧 import 的是 .so，不是 @shengwang/rtm-full', () {
      expect(arktsManager, contains("from 'libagora-rtm-sdk.so'"));
      expect(
        arktsManager,
        isNot(contains("from '@shengwang/rtm-full'")),
        reason: 'bytecode HAR 已弃用，改直连 NAPI',
      );
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

    test('Map 结果必须带 ok 字段（否则 Dart 一律当失败）', () {
      // 628 遗留 bug：getOnlineUsers / getChannelMetadata 直接 result.success(data)，
      // 返回的 Map 没有 ok，Dart `_invoke` 走 `r['ok'] == true` 判定为失败。
      for (final m in ['getOnlineUsers', 'setChannelMetadata', 'getChannelMetadata']) {
        final start = arktsPlugin.indexOf("case '$m':");
        expect(start, greaterThan(0), reason: '找不到 case $m');
        // 取该 case 到下一个 case 之间的片段。
        final next = arktsPlugin.indexOf("case '", start + 10);
        final body =
            arktsPlugin.substring(start, next > 0 ? next : arktsPlugin.length);
        expect(body, contains("out.set('ok', true)"),
            reason: '$m 的返回值缺 ok 字段');
      }
    });
  });

  group('③ 工厂路由', () {
    test('ohos 返回 OhosRtmBackend（不是 Unsupported）', () {
      expect(factory, contains("Platform.operatingSystem == 'ohos'"));
      expect(factory, contains('OhosRtmBackend()'));
      expect(factory, isNot(contains('UnsupportedRtmBackend();\n  }\n  if (Platform.isMacOS')));
    });

    test('macOS / Linux 仍降级', () {
      expect(factory, contains('UnsupportedRtmBackend()'));
      expect(factory, contains('Platform.isMacOS || Platform.isLinux'));
    });
  });

  group('④ NAPI API 用法与实测签名匹配', () {
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
      expect(arktsManager, contains('resp.data'));
      expect(arktsManager, contains('RtmGetChannelMetadataResponse'));
    });

    test('setChannelMetadata 不回读 revision（响应无该字段）', () {
      // 实测：SetChannelMetadataResponse 只有 channelName/channelType。
      expect(arktsManager, isNot(contains('resp.metadata')));
      expect(arktsManager, contains('return \'\';'));
    });

    test('whoNow 用 instanceId + channelType=MESSAGE', () {
      // NAPI 签名：(instanceId, channelName, channelType, options)
      expect(arktsManager, contains('whoNow(id, channel, CHANNEL_TYPE_MESSAGE, options)'));
      expect(arktsManager, contains('CHANNEL_TYPE_MESSAGE: number = 1'));
      expect(arktsManager, contains('totalOccupancy'));
      expect(arktsManager, contains('userStateList'));
    });

    test('subscribe 传 withMessage + withPresence', () {
      expect(arktsManager, contains('withMessage: true'));
      expect(arktsManager, contains('withPresence: true'));
    });

    test('publish 传 channelType: MESSAGE', () {
      expect(arktsManager, contains('channelType: CHANNEL_TYPE_MESSAGE'));
      expect(arktsManager, contains('customType'));
    });

    test('实例句柄用 instanceId（-1 表示未创建）', () {
      expect(arktsManager, contains('private instanceId: number = -1'));
      expect(arktsManager, contains('createRtmClient(config)'));
      expect(arktsManager, contains('releaseRtmClient(this.instanceId)'));
    });

    test('三个事件监听都用 addEventListener(instanceId, ...)', () {
      for (final ev in ['message', 'presence', 'linkState']) {
        expect(arktsManager, contains("addEventListener(id, '$ev'"),
            reason: '缺 $ev 事件监听');
      }
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

  group('⑥ 鸿蒙加入房间的取码途径（631）', () {
    final roomMenu =
        File('lib/widgets/room_menu_button.dart').readAsStringSync();
    final scanner = File(
      'lib/screens/room/qr_scanner_screen.dart',
    ).readAsStringSync();
    final picker = File('lib/utils/gallery_picker.dart').readAsStringSync();

    test('房间码支持鸿蒙从相册选图（不再硬编码拦截）', () {
      // 631 前：_pickRoomCodeFromImage 里 `if (ohos) return null`。
      // 631 后：鸿蒙与 Windows 同走相册 + 纯 Dart 解码。
      expect(roomMenu, contains('GalleryPicker.pickImage'));
      expect(roomMenu, contains('GalleryPicker.isOhos'));
      expect(roomMenu, contains('galleryOnly'));
    });

    test('相册选图在鸿蒙走 file_picker（image_picker 无鸿蒙实现）', () {
      expect(picker, contains('FileType.image'));
      expect(picker, contains('FilePicker.platform.pickFiles'));
    });

    test('相机扫码页的鸿蒙提示引导到「从相册选图」', () {
      expect(scanner, contains('鸿蒙暂不支持相机扫码'));
      expect(scanner, contains('从相册选图'));
      expect(scanner, contains('手动输入房间码'));
    });
  });
}

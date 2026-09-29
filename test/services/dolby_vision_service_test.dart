import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/dolby_vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(DolbyVisionService.resetCache);

  group('DvDecoder', () {
    test('解析平台返回的解码器条目', () {
      final d = DvDecoder.fromMap(const {
        'name': 'c2.qti.hevc.decoder',
        'mime': 'video/hevc',
        'dvProfiles': [0x0103, 0x0109],
        'isSoftware': false,
      });
      expect(d.shortName, 'hevc.decoder');
      expect(d.display, 'hevc.decoder (hevc, p0103/0109)');
    });

    test('shortName 去掉厂商前缀', () {
      String short(String n) => DvDecoder.fromMap({'name': n}).shortName;
      expect(short('c2.qti.hevc.decoder'), 'hevc.decoder');
      expect(short('c2.android.avc.decoder'), 'avc.decoder');
      expect(short('OMX.MS.HEVCDV.Decoder'), 'HEVCDV.Decoder');
      expect(short('OMX.RTK.video.decoder.tunneled'), 'video.decoder.tunneled');
    });

    test('软件解码器被正确标记', () {
      final d = DvDecoder.fromMap(const {
        'name': 'c2.android.hevc.decoder',
        'mime': 'video/dolby-vision',
        'dvProfiles': <int>[],
        'isSoftware': true,
      });
      expect(d.isSoftware, isTrue);
    });

    test('缺失字段时安全降级', () {
      final d = DvDecoder.fromMap(const {});
      expect(d.name, '?');
      expect(d.dvProfiles, isEmpty);
      expect(d.isSoftware, isFalse);
    });
  });

  group('DvProbeResult.summary', () {
    test('硬件解码器存在时标记为支持硬解', () {
      const p = DvProbeResult(
        supported: true,
        hardware: true,
        decoders: [
          DvDecoder(
            name: 'c2.qti.hevc.decoder',
            mime: 'video/hevc',
            dvProfiles: [0x0109],
            isSoftware: false,
          ),
        ],
      );
      expect(p.summary, contains('支持硬解'));
      expect(p.summary, isNot(contains('仅软解')));
    });

    test('只有软件解码器时标记为仅软解', () {
      const p = DvProbeResult(
        supported: true,
        hardware: false,
        decoders: [
          DvDecoder(
            name: 'c2.android.hevc.decoder',
            mime: 'video/dolby-vision',
            dvProfiles: <int>[],
            isSoftware: true,
          ),
        ],
      );
      expect(p.summary, contains('仅软解'));
    });

    test('探测异常时展示错误而非静默失败', () {
      const p = DvProbeResult(
        supported: false,
        hardware: false,
        decoders: [],
        error: 'NullPointerException',
      );
      expect(p.summary, contains('探测失败'));
      expect(p.summary, contains('NullPointerException'));
    });

    test('无解码器时明确说明', () {
      expect(DvProbeResult.unknown.summary, '未发现 DV 解码器');
    });
  });

  group('DolbyVisionService.probe', () {
    const channel = MethodChannel('com.himi/dolby_vision');

    setUp(() => DolbyVisionService.isAndroidOverride = true);

    void mockProbe(Map<Object?, Object?> result) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getDolbyVisionInfo');
        return result;
      });
    }

    test('通过 video/hevc + DV profile 判定为硬解（骁龙场景）', () async {
      // 这是导致卡顿的关键场景：设备有 DV 能力，但只在 video/hevc 上
      // 声明，旧实现只认 video/dolby-vision 会漏判并强制软解。
      mockProbe(const {
        'supported': true,
        'hardware': true,
        'error': null,
        'decoders': [
          {
            'name': 'c2.qti.hevc.decoder',
            'mime': 'video/hevc',
            'dvProfiles': [0x0103, 0x0109],
            'isSoftware': false,
          },
        ],
      });

      final p = await DolbyVisionService.probe();
      expect(p.supported, isTrue);
      expect(p.hardware, isTrue);
      expect(p.decoders.single.mime, 'video/hevc');
      expect(p.decoders.single.dvProfiles, [0x0103, 0x0109]);
    });

    test('厂商私有 MIME 也能被识别', () async {
      mockProbe(const {
        'supported': true,
        'hardware': true,
        'error': null,
        'decoders': [
          {
            'name': 'OMX.MS.HEVCDV.Decoder',
            'mime': 'video/hevcdv',
            'dvProfiles': <int>[],
            'isSoftware': false,
          },
        ],
      });

      final p = await DolbyVisionService.probe();
      expect(p.hardware, isTrue);
      expect(p.decoders.single.mime, 'video/hevcdv');
    });

    test('探测异常时返回错误信息而非静默 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });

      final p = await DolbyVisionService.probe();
      expect(p.supported, isFalse);
      expect(p.hardware, isFalse);
      expect(p.error, isNotNull);
    });

    test('非 Android 平台直接返回，不调用平台通道', () async {
      DolbyVisionService.isAndroidOverride = false;
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return const {};
      });

      final p = await DolbyVisionService.probe();
      expect(called, isFalse);
      expect(p.error, '非 Android 平台');
    });

    test('结果被缓存，不重复调用平台', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return const {'supported': true, 'hardware': true, 'decoders': []};
      });

      await DolbyVisionService.probe();
      await DolbyVisionService.probe();
      await DolbyVisionService.probe();
      expect(calls, 1);
    });
  });

  group('DolbyVisionService.selectDecoder', () {
    const channel = MethodChannel('com.himi/dolby_vision');

    setUp(() => DolbyVisionService.isAndroidOverride = true);

    void mockSelect(Map<Object?, Object?> result, void Function(MethodCall)? onCall) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        onCall?.call(call);
        return result;
      });
    }

    test('解析平台预选出的底层 codec 名', () async {
      mockSelect(const {
        'picked': 'c2.qti.hevc.decoder',
        'mime': 'video/hevc',
        'isSoftware': false,
        'supported': ['c2.qti.hevc.decoder', 'c2.android.hevc.decoder'],
        'dvProfiles': [0x0103, 0x0109],
        'error': null,
      }, null);

      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(s.hasPicked, isTrue);
      expect(s.picked, 'c2.qti.hevc.decoder');
      expect(s.mime, 'video/hevc');
      expect(s.isSoftware, isFalse);
      expect(s.supported, hasLength(2));
      expect(s.dvProfiles, [0x0103, 0x0109]);
    });

    test('DV 内容把 dolbyVision 标记与尺寸一并传给原生', () async {
      MethodCall? seen;
      mockSelect(const {'picked': 'c2.qti.hevc.decoder'}, (c) => seen = c);

      await DolbyVisionService.selectDecoder(
        mime: 'video/hevc',
        width: 3840,
        height: 1608,
        dolbyVision: true,
      );

      expect(seen?.method, 'selectDecoder');
      final args = Map<Object?, Object?>.from(seen!.arguments as Map);
      expect(args['mime'], 'video/hevc');
      expect(args['width'], 3840);
      expect(args['height'], 1608);
      expect(args['dolbyVision'], isTrue);
    });

    test('软件 codec 被正确标记，交由上层判为软解', () async {
      mockSelect(const {
        'picked': 'c2.android.hevc.decoder',
        'isSoftware': true,
      }, null);

      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(s.isSoftware, isTrue);
    });

    test('无匹配解码器时 hasPicked 为 false', () async {
      mockSelect(const {'picked': null, 'error': '无匹配解码器'}, null);
      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(s.hasPicked, isFalse);
      expect(s.display, '探测失败');
    });

    test('缺失字段按 null 解析，不抛异常', () async {
      mockSelect(const <Object?, Object?>{}, null);
      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(s.hasPicked, isFalse);
      expect(s.isSoftware, isNull);
      expect(s.supported, isEmpty);
      expect(s.dvProfiles, isEmpty);
    });

    test('探测异常时返回错误信息', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(s.error, isNotNull);
    });

    test('非 Android 平台不调用平台通道', () async {
      DolbyVisionService.isAndroidOverride = false;
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return const {};
      });

      final s = await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(called, isFalse);
      expect(s.error, '非 Android 平台');
    });

    test('结果不缓存——格式变化时需重新探测', () async {
      var calls = 0;
      mockSelect(const {'picked': 'c2.qti.hevc.decoder'}, (_) => calls++);

      await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      await DolbyVisionService.selectDecoder(mime: 'video/hevc');
      expect(calls, 2);
    });
  });

  group('DolbyVisionService.buildIdentity', () {
    const channel = MethodChannel('com.himi/dolby_vision');

    setUp(() => DolbyVisionService.isAndroidOverride = true);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mockVersion(Map<Object?, Object?> result) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getAppVersion');
        return result;
      });
    }

    test('解析版本号并确认通道已注册', () async {
      mockVersion(const {'versionName': '1.1.16', 'versionCode': 186, 'error': null});

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isTrue);
      expect(id.channelMissing, isFalse);
      expect(id.versionName, '1.1.16');
      expect(id.versionCode, 186);
      expect(id.hasVersion, isTrue);
      expect(id.summary, '1.1.16+186 | DV通道已注册');
    });

    test('版本号为空串时回落到未知，不输出空版本', () async {
      mockVersion(const {'versionName': '', 'versionCode': 0, 'error': null});

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isTrue);
      expect(id.hasVersion, isFalse);
      expect(id.summary, '未知 | DV通道已注册');
    });

    test('原生报错时保留错误文本', () async {
      mockVersion(const {
        'versionName': null,
        'versionCode': null,
        'error': 'java.lang.IllegalStateException',
      });

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isTrue);
      expect(id.summary, contains('java.lang.IllegalStateException'));
    });

    test('versionCode 为小数也能解析', () async {
      mockVersion(const {'versionName': '1.1.16', 'versionCode': 186.0, 'error': null});
      final id = await DolbyVisionService.buildIdentity();
      expect(id.versionCode, 186);
    });

    // 核心场景：CI 曾整体覆盖 android/ 导致原生插件未随包发布，
    // 真机表现为 MissingPluginException。报告必须一眼看出这一点。
    test('通道未注册时点明产物缺原生插件', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isFalse);
      expect(id.channelMissing, isTrue);
      expect(id.versionName, isNull);
      expect(id.summary, '未知 | DV通道未注册(产物缺原生插件)');
      expect(id.error, contains('MissingPluginException'));
    });

    test('原生抛异常同样判为通道未应答', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isFalse);
      expect(id.summary, '未知 | DV通道未注册(产物缺原生插件)');
    });

    test('非 Android 平台不调用平台通道', () async {
      DolbyVisionService.isAndroidOverride = false;
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return const {};
      });

      final id = await DolbyVisionService.buildIdentity();
      expect(called, isFalse);
      expect(id.channelOk, isFalse);
      expect(id.error, '非 Android 平台');
    });

    test('原生返回空数据时不误报版本，通道仍视为已注册', () async {
      // 通道应答了就说明插件在包里；数据缺失只影响版本展示，
      // 不能因此把「通道未注册」的结论写进报告。
      mockVersion(const <Object?, Object?>{});

      final id = await DolbyVisionService.buildIdentity();
      expect(id.channelOk, isTrue);
      expect(id.hasVersion, isFalse);
      expect(id.summary, '未知 | DV通道已注册');
    });
  });
}

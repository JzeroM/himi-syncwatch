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
}

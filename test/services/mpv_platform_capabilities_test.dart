import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('himi_mpv_android'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('himi_mpv_windows'),
      null,
    );
  });

  test('Android HDR 能力解析', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('himi_mpv_android'),
      (call) async => <Object?, Object?>{
        'formats': <Object?>['hdr10', 'hlg'],
      },
    );
    final caps = await HimiMpvAndroidSession.queryHdrCapabilities();
    expect(caps.hdr10, isTrue);
    expect(caps.hlg, isTrue);
    expect(caps.displayHdr, isTrue);
  });

  test('Windows HDR 能力解析', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('himi_mpv_windows'),
      (call) async => <Object?, Object?>{
        'formats': <Object?>['hdr10'],
      },
    );
    final caps = await HimiMpvWindowsSession.queryHdrCapabilities();
    expect(caps.hdr10, isTrue);
    expect(caps.hlg, isFalse);
    expect(caps.displayHdr, isTrue);
  });
}

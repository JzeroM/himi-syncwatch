import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('himi_mpv');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('create 以原生返回的 nativeSurface/hdrOutput 为准，不用 textureId 反推', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') {
        return <String, Object?>{
          'textureId': 2,
          'nativeSurface': false,
          'hdrOutput': false,
        };
      }
      return null;
    });

    final player = await HimiMpvPlayer.create(nativeSurface: true, hdr: true);
    expect(player.textureId, 2);
    expect(player.usesNativeSurface, isFalse);
    expect(player.hdrOutputActive, isFalse);
  });

  test('create 返回 Surface 时使用原生确认状态', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') {
        return <String, Object?>{
          'textureId': 0,
          'nativeSurface': true,
          'hdrOutput': true,
        };
      }
      return null;
    });

    final player = await HimiMpvPlayer.create(nativeSurface: true, hdr: true);
    expect(player.textureId, 0);
    expect(player.usesNativeSurface, isTrue);
    expect(player.hdrOutputActive, isTrue);
  });
}

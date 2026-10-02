import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';

  group('AndroidManifest Impeller 配置', () {
    test('EnableImpeller 显式声明且为 false（fvp 纹理路径依赖）', () {
      final xml = File(manifestPath).readAsStringSync();
      final match = RegExp(
        '<meta-data\\s+'
        'android:name="io\\.flutter\\.embedding\\.android\\.EnableImpeller"\\s+'
        'android:value="([^"]+)"',
        multiLine: true,
      ).firstMatch(xml);

      expect(
        match,
        isNotNull,
        reason: '必须显式声明 EnableImpeller meta-data：'
            '删除后 fvp 按 false 注册 SurfaceTexture，'
            '而引擎缺省开启 Impeller，会错配导致黑屏',
      );
      expect(
        match!.group(1),
        'false',
        reason: '必须为 false：Impeller 外部纹理合成在部分设备'
            '（如 RK3528 盒子）黑帧，Skia + SurfaceTexture 才是可用组合',
      );
    });
  });
}

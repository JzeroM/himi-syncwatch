import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/test_fakes.dart';

void main() {
  group('GlassParamSpec（滑杆规格单一事实源）', () {
    test('7 个参数、key 唯一、默认值均在范围内', () {
      expect(glassParamSpecs, hasLength(7));
      final keys = glassParamSpecs.map((s) => s.key).toList();
      expect(keys.toSet(), hasLength(7));
      expect(
        keys,
        [
          'glassBlur',
          'glassThickness',
          'glassEdgeZone',
          'glassSaturation',
          'glassChromatic',
          'glassLightIntensity',
          'glassRefractiveIndex',
        ],
      );
      for (final spec in glassParamSpecs) {
        expect(spec.defaultValue, inInclusiveRange(spec.min, spec.max),
            reason: '${spec.key} 默认值越界');
        expect(spec.divisions, greaterThan(0));
      }
      expect(
        glassParamSpecs.firstWhere((s) => s.key == 'glassChromatic').decimals,
        3,
        reason: '色散数值极小，需 3 位小数回显',
      );
      final edgeZone =
          glassParamSpecs.firstWhere((s) => s.key == 'glassEdgeZone');
      expect(edgeZone.min, 20, reason: '折射范围滑杆下限 20（设备 round-7）');
      expect(edgeZone.max, 24, reason: '折射范围滑杆上限 24');
      expect(edgeZone.defaultValue, 20, reason: '默认折射范围 20');
      expect(edgeZone.divisions, 4, reason: '20~24 整数四档');
      expect(edgeZone.decimals, 0, reason: '整数回显');
    });

    test('read：有值读值，null 回默认', () {
      final tuning = const GlassTuning(blur: 9, thickness: null);
      final blurSpec = glassParamSpecs.firstWhere((s) => s.key == 'glassBlur');
      final thicknessSpec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassThickness');
      final edgeZoneSpec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassEdgeZone');
      expect(blurSpec.read(tuning), 9);
      expect(thicknessSpec.read(tuning), thicknessSpec.defaultValue);
      expect(edgeZoneSpec.read(tuning), 20, reason: 'null 回默认 20');
      expect(edgeZoneSpec.read(const GlassTuning(edgeZone: 23)), 23);
    });

    test('apply：写回对应字段且不动其余字段', () {
      const s = AppSettings(glassBlur: 3, glassThickness: 44);
      final spec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassSaturation');
      final out = spec.apply(s, 2.2);
      expect(out.glassSaturation, 2.2);
      expect(out.glassBlur, 3, reason: '无关字段保留');
      expect(out.glassThickness, 44);

      final edgeZoneSpec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassEdgeZone');
      final out2 = edgeZoneSpec.apply(s, 22);
      expect(out2.glassEdgeZone, 22);
      expect(out2.glassBlur, 3, reason: '无关字段保留');
      expect(out2.glassThickness, 44);
    });
  });

  group('GlassTuning', () {
    test('fromSettings 映射 6 字段', () {
      const s = AppSettings(
        glassBlur: 7,
        glassThickness: 25,
        glassEdgeZone: 22,
        glassSaturation: 1.8,
        glassChromatic: 0.02,
        glassLightIntensity: 0.6,
      );
      final t = GlassTuning.fromSettings(s);
      expect(t.blur, 7);
      expect(t.thickness, 25);
      expect(t.edgeZone, 22);
      expect(t.saturation, 1.8);
      expect(t.chromatic, 0.02);
      expect(t.lightIntensity, 0.6);
      expect(t.isDefault, isFalse);
    });

    test('isDefault：全 null 才是默认', () {
      expect(const GlassTuning().isDefault, isTrue);
      expect(const GlassTuning(blur: 5).isDefault, isFalse);
    });

    test('toThemeData 产出包主题', () {
      const GlassTuning(
        blur: 8,
        thickness: 30,
        saturation: 1.7,
        chromatic: 0.03,
        lightIntensity: 0.7,
      ).toThemeData();
      expect(const GlassTuning().toThemeData(), isA<GlassThemeData>());
    });

    test('toThemeData：null 字段兜底到应用默认（Kyant 目标观感，v1.1.85）', () {
      final s = const GlassTuning().toThemeData().light.settings!;
      expect(s.blur, glassDefault('glassBlur'));
      expect(s.blur, 4, reason: '磨砂默认 4');
      expect(s.thickness, glassDefault('glassThickness'));
      expect(s.thickness, 28, reason: '厚度默认 28');
      expect(s.saturation, glassDefault('glassSaturation'));
      expect(s.saturation, 1.7);
      expect(s.chromaticAberration, glassDefault('glassChromatic'));
      expect(s.chromaticAberration, 0.15, reason: '色散默认 0.15（对齐图中彩虹圈）');
      expect(s.lightIntensity, glassDefault('glassLightIntensity'));
      expect(s.lightIntensity, 1.2, reason: '高光默认 1.2');
    });

    test('toThemeData：显式值优先于默认兜底', () {
      final s = const GlassTuning(chromatic: 0.3, blur: 9)
          .toThemeData()
          .light
          .settings!;
      expect(s.chromaticAberration, 0.3);
      expect(s.blur, 9);
      expect(s.thickness, glassDefault('glassThickness'),
          reason: '未显式设置的字段仍走默认兜底');
    });
  });

  group('glassDefault（应用默认值 helper）', () {
    test('6 个 key 返回与 spec 一致的默认值', () {
      for (final key in const [
        'glassBlur',
        'glassThickness',
        'glassEdgeZone',
        'glassSaturation',
        'glassChromatic',
        'glassLightIntensity',
        'glassRefractiveIndex',
      ]) {
        expect(
          glassDefault(key),
          glassParamSpecs.firstWhere((s) => s.key == key).defaultValue,
          reason: '$key 与 spec 同源',
        );
      }
    });

    test('未知 key 抛 StateError', () {
      expect(() => glassDefault('nope'), throwsStateError);
    });
  });

  group('glassEdgeZoneVisible（折射范围滑杆可见性：Android/iOS 非 TV）', () {
    test('Android 非 TV 显示', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(glassEdgeZoneVisible(tvMode: false), isTrue);
    });

    test('iOS 非 TV 也显示（standard 路径读 uEdgeZone）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(glassEdgeZoneVisible(tvMode: false), isTrue);
    });

    test('TV 模式隐藏（遥控器方向键会被滑杆吞键）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(glassEdgeZoneVisible(tvMode: true), isFalse);
    });

    test('桌面/Web 平台隐藏', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final p in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(glassEdgeZoneVisible(tvMode: false), isFalse,
            reason: '$p 不显示折射范围滑杆');
      }
    });
  });

  group('glassRefractiveIndexVisible（折射强度滑杆：全平台隐藏）', () {
    test('所有平台均隐藏（standard 路径该参数影响很小）', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(glassRefractiveIndexVisible(tvMode: false), isFalse,
            reason: '$p 不显示折射强度滑杆');
        expect(glassRefractiveIndexVisible(tvMode: true), isFalse);
      }
    });
  });

  group('iOS 专属调参（standard 路径，更透亮）', () {
    test('iOS 的 glassDefault 用 GlassIosStandard 微调组', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(glassDefault('glassBlur'), GlassIosStandard.blur);
      expect(glassDefault('glassThickness'), GlassIosStandard.thickness);
      expect(glassDefault('glassSaturation'), GlassIosStandard.saturation);
      expect(
          glassDefault('glassLightIntensity'), GlassIosStandard.lightIntensity);
      // 非微调项仍与 spec 同源
      expect(
        glassDefault('glassChromatic'),
        glassParamSpecs
            .firstWhere((s) => s.key == 'glassChromatic')
            .defaultValue,
      );
      // 微调方向：比 spec 默认更透亮（降模糊/厚度/高光、升饱和）
      final blurSpec = glassParamSpecs.firstWhere((s) => s.key == 'glassBlur');
      expect(GlassIosStandard.blur, lessThan(blurSpec.defaultValue));
      expect(
          GlassIosStandard.thickness,
          lessThan(glassParamSpecs
              .firstWhere((s) => s.key == 'glassThickness')
              .defaultValue));
      expect(
          GlassIosStandard.lightIntensity,
          lessThan(glassParamSpecs
              .firstWhere((s) => s.key == 'glassLightIntensity')
              .defaultValue));
    });

    test('iOS toThemeData 不强制 premium 画质且降环境白光', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final data = const GlassTuning().toThemeData();
      expect(data.light.quality, isNull,
          reason: '不再对 iOS 强制 GlassQuality.premium');
      expect(data.light.settings?.ambientStrength,
          GlassIosStandard.ambientStrength);
    });

    test('iOS 走 GlassBodyMode.clear（去 standard PATH B 的硬编码霜底/灰化）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final data = const GlassTuning().toThemeData();
      expect(data.dark.settings?.bodyMode, GlassBodyMode.clear);
      expect(data.light.settings?.bodyMode, GlassBodyMode.clear);
      // 传到真正渲染用的 LiquidGlassSettings
      final resolved = data.dark.settings!.applyTo(const LiquidGlassSettings());
      expect(resolved.bodyMode, GlassBodyMode.clear);
    });

    test('iOS clear 模式体色全透明（glassColor alpha=0）+ 降饱和/去模糊/降高光', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = const GlassTuning().toThemeData().dark.settings!;
      expect(s.glassColor!.a, GlassIosStandard.glassColorAlpha);
      expect(s.glassColor!.a, 0.0, reason: '体色全透明 → 背景最大透出');
      expect(s.blur, GlassIosStandard.blur);
      expect(s.blur, 0);
      expect(s.saturation, GlassIosStandard.saturation);
      expect(s.lightIntensity, GlassIosStandard.lightIntensity);
    });

    test('安卓/其余平台 bodyMode 保持默认 adaptive（不传）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final data = const GlassTuning().toThemeData();
      expect(data.dark.settings?.bodyMode, isNull, reason: '未覆盖 → 交给包默认');
      final resolved = data.dark.settings!.applyTo(const LiquidGlassSettings());
      expect(resolved.bodyMode, GlassBodyMode.adaptive);
    });

    test('安卓沿用 spec 默认（不受 iOS 微调影响）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        glassDefault('glassThickness'),
        glassParamSpecs
            .firstWhere((s) => s.key == 'glassThickness')
            .defaultValue,
      );
      expect(
        glassDefault('glassBlur'),
        glassParamSpecs.firstWhere((s) => s.key == 'glassBlur').defaultValue,
      );
    });
  });

  group('glassTuningProvider（settings → tuning 实时联动）', () {
    ProviderContainer makeContainer(AppSettings initial) {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => FakeSettingsNotifier(initial)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('初始映射', () {
      final c = makeContainer(const AppSettings(glassBlur: 6));
      expect(c.read(glassTuningProvider).blur, 6);
      expect(c.read(glassTuningProvider).isDefault, isFalse);
    });

    test('update 写入后 provider 即时跟随', () async {
      final c = makeContainer(const AppSettings());
      expect(c.read(glassTuningProvider).isDefault, isTrue);

      await c
          .read(settingsProvider.notifier)
          .update(glassThickness: 35, glassSaturation: 2.0);
      final t = c.read(glassTuningProvider);
      expect(t.thickness, 35);
      expect(t.saturation, 2.0);
      expect(t.blur, isNull, reason: '未动的字段保持 null（渲染走应用默认）');
    });

    test('恢复默认（显式 null）后回到 isDefault', () async {
      final c = makeContainer(const AppSettings(glassBlur: 9));
      await c.read(settingsProvider.notifier).update(
            glassBlur: null,
            glassThickness: null,
            glassEdgeZone: null,
            glassSaturation: null,
            glassChromatic: null,
            glassLightIntensity: null,
            glassRefractiveIndex: null,
          );
      expect(c.read(glassTuningProvider).isDefault, isTrue);
    });

    test('无关设置变化不改变 tuning 快照值', () async {
      final c = makeContainer(const AppSettings(glassBlur: 6));
      final before = c.read(glassTuningProvider);
      await c.read(settingsProvider.notifier).update(tvMode: true);
      final after = c.read(glassTuningProvider);
      expect(after.blur, before.blur);
      expect(after.isDefault, before.isDefault);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/test_fakes.dart';

void main() {
  group('GlassParamSpec（滑杆规格单一事实源）', () {
    test('5 个参数、key 唯一、默认值均在范围内', () {
      expect(glassParamSpecs, hasLength(5));
      final keys = glassParamSpecs.map((s) => s.key).toList();
      expect(keys.toSet(), hasLength(5));
      expect(
        keys,
        [
          'glassBlur',
          'glassThickness',
          'glassSaturation',
          'glassChromatic',
          'glassLightIntensity',
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
    });

    test('read：有值读值，null 回默认', () {
      final tuning = const GlassTuning(blur: 9, thickness: null);
      final blurSpec = glassParamSpecs.firstWhere((s) => s.key == 'glassBlur');
      final thicknessSpec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassThickness');
      expect(blurSpec.read(tuning), 9);
      expect(thicknessSpec.read(tuning), thicknessSpec.defaultValue);
    });

    test('apply：写回对应字段且不动其余字段', () {
      const s = AppSettings(glassBlur: 3, glassThickness: 44);
      final spec =
          glassParamSpecs.firstWhere((s) => s.key == 'glassSaturation');
      final out = spec.apply(s, 2.2);
      expect(out.glassSaturation, 2.2);
      expect(out.glassBlur, 3, reason: '无关字段保留');
      expect(out.glassThickness, 44);
    });
  });

  group('GlassTuning', () {
    test('fromSettings 映射 5 字段', () {
      const s = AppSettings(
        glassBlur: 7,
        glassThickness: 25,
        glassSaturation: 1.8,
        glassChromatic: 0.02,
        glassLightIntensity: 0.6,
      );
      final t = GlassTuning.fromSettings(s);
      expect(t.blur, 7);
      expect(t.thickness, 25);
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
    test('5 个 key 返回与 spec 一致的默认值', () {
      for (final key in const [
        'glassBlur',
        'glassThickness',
        'glassSaturation',
        'glassChromatic',
        'glassLightIntensity',
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
            glassSaturation: null,
            glassChromatic: null,
            glassLightIntensity: null,
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

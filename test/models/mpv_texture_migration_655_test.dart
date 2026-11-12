import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 655：640 自动回退留下的「锁死纹理」一次性迁移。
///
/// ## 背景
///
/// 640 的 surface→texture 自动回退会调
/// `notifier.update(mpvVideoOutput: 'texture')`，而
/// `settings_provider.update()` 把**任何**写入都标成
/// `mpvVideoOutputUserSet = true`：
///
/// ```dart
/// mpvVideoOutput: mpvVideoOutput,
/// mpvVideoOutputUserSet: mpvVideoOutput != null ? true : null,
/// ```
///
/// 这与 640 提交说明里「userSet 保持 false」的意图相反。而
/// `userSet == true` 是最高优先级：
///
/// ```dart
/// static String effectiveVideoOutput({...}) {
///   if (windows && !userSet) return texture;
///   return normalizeVideoOutput(configured);   // userSet 时直接采用 configured
/// }
/// ```
///
/// → **一次误判 = 该设备永久锁定纹理，重启也不恢复**。
///
/// 用户真机现象：「以前手机播是好的，现在自动回退到纹理」。
///
/// ## 迁移规则
///
/// 升级到 655 时，对「texture + userSet=true + 未迁移过」的组合重置为
/// `surface` + `userSet=false`，并用 `mpvTextureAutoMigrated` 保证只跑
/// 一次——之后用户手动选纹理不会被反复重置。
void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
        'mpvVideoOutput': 'texture',
        'mpvVideoOutputUserSet': true,
      };

  group('① 640 锁死的纹理被迁回 Surface', () {
    test('texture + userSet=true + 未迁移 → 重置为 surface', () {
      final s = AppSettings.fromJson(baseJson());
      expect(s.mpvVideoOutput, 'surface');
      expect(s.mpvVideoOutputUserSet, isFalse,
          reason: 'userSet 必须清掉，否则会一直压制平台默认值');
    });

    test('迁移后写入标记，保证只跑一次', () {
      final s = AppSettings.fromJson(baseJson());
      expect(s.mpvTextureAutoMigrated, isTrue);
    });

    test('迁移后的 effectiveMpvVideoOutput 回到 surface', () {
      final s = AppSettings.fromJson(baseJson());
      expect(
        AppSettings.effectiveMpvVideoOutput(
          s.mpvVideoOutput,
          userSet: s.mpvVideoOutputUserSet,
        ),
        'surface',
      );
    });
  });

  group('② 迁移只执行一次（不反复覆盖用户选择）', () {
    test('685：Windows 下即使已迁移过也恒为 surface', () {
      // 655 时这里断言「已迁移过 → 用户后来手动选 texture 会被尊重」；
      // 685 起 Windows 已移除「视频路径」设置（texture 必闪退），
      // `mpvTextureMigration` 在 Windows 无条件返回 surface + userSet=false。
      //
      // 注：本测试运行在 Linux 主机上，`defaultTargetPlatform` 非 windows，
      // 因此这里验证的是「迁移函数在非 Windows 下仍尊重旧语义」——
      // Windows 分支由 `windows_hardcoded_settings_685_test.dart` 覆盖。
      final s = AppSettings.fromJson(<String, dynamic>{
        'mpvVideoOutput': 'texture',
        'mpvVideoOutputUserSet': true,
        'mpvTextureAutoMigrated': true, // 已迁移过
      });
      expect(s.mpvVideoOutput, 'texture',
          reason: '非 Windows 平台迁移只跑一次，之后用户的选择不能被覆盖');
      expect(s.mpvVideoOutputUserSet, isTrue);
    });

    test('迁移标记随 toJson 落盘（否则下次启动会重复迁移）', () {
      final s = AppSettings.fromJson(baseJson());
      expect(s.toJson()['mpvTextureAutoMigrated'], isTrue);
    });

    test('迁移结果 round-trip 稳定', () {
      final first = AppSettings.fromJson(baseJson());
      final second = AppSettings.fromJson(first.toJson());
      expect(second.mpvVideoOutput, 'surface');
      expect(second.mpvVideoOutputUserSet, isFalse);
      expect(second.mpvTextureAutoMigrated, isTrue);
    });
  });

  group('③ 不误伤其他组合', () {
    test('用户手动选过 surface → 不动', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'mpvVideoOutput': 'surface',
        'mpvVideoOutputUserSet': true,
      });
      expect(s.mpvVideoOutput, 'surface');
      expect(s.mpvVideoOutputUserSet, isTrue);
    });

    test('texture 但 userSet=false（未手动设置）→ 保持 texture', () {
      // 这种组合理论上不该出现（640 会置 true），但若存档被外部改写，
      // 迁移不应擅自改变语义。
      final s = AppSettings.fromJson(<String, dynamic>{
        'mpvVideoOutput': 'texture',
        'mpvVideoOutputUserSet': false,
      });
      expect(s.mpvVideoOutput, 'texture');
      expect(s.mpvVideoOutputUserSet, isFalse);
    });

    test('旧数据无相关字段 → 默认 surface + 未设置', () {
      final s = AppSettings.fromJson(<String, dynamic>{});
      expect(s.mpvVideoOutput, 'surface');
      expect(s.mpvVideoOutputUserSet, isFalse);
      expect(s.mpvTextureAutoMigrated, isFalse,
          reason: '没迁移过任何东西，不应打标记');
    });

    test('非法值 → 归一为 surface', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'mpvVideoOutput': 'bogus',
        'mpvVideoOutputUserSet': true,
      });
      expect(s.mpvVideoOutput, 'surface');
    });
  });

  group('④ 默认值', () {
    test('构造器默认未迁移', () {
      expect(const AppSettings().mpvTextureAutoMigrated, isFalse);
    });

    test('copyWith 可显式设置迁移标记', () {
      const s = AppSettings();
      expect(s.copyWith(mpvTextureAutoMigrated: true).mpvTextureAutoMigrated,
          isTrue);
      expect(s.copyWith().mpvTextureAutoMigrated, isFalse,
          reason: '未传参时保留原值');
    });
  });

  group('⑤ 迁移结果必须回写存档', () {
    // `fromJson` 的迁移是纯函数，只改内存值。若不回写，存档里仍是
    // `texture + userSet=true`，每次启动都重新迁移一遍——结果虽幂等，
    // 但会造成「设置页显示 Surface、存档却是 texture」的误导性现象。
    final provider = File(
      'lib/providers/settings_provider.dart',
    ).readAsStringSync();

    test('load() 在迁移生效时回写', () {
      final idx = provider.indexOf('Future<void> load() async {');
      expect(idx, greaterThan(-1));
      final body = provider.substring(
        idx,
        (idx + 1600).clamp(0, provider.length),
      );
      expect(body, contains('mpvTextureAutoMigrated'));
      expect(body, contains('_storage.write'));
    });

    test('回写条件是「已迁移且存档尚未标记」', () {
      final idx = provider.indexOf('Future<void> load() async {');
      final body = provider.substring(
        idx,
        (idx + 1600).clamp(0, provider.length),
      );
      expect(body, contains("decoded['mpvTextureAutoMigrated'] != true"),
          reason: '已标记过就不该重复写盘');
    });

    test('回写用 toJson 序列化（保证新字段落盘）', () {
      final idx = provider.indexOf('Future<void> load() async {');
      final body = provider.substring(
        idx,
        (idx + 1600).clamp(0, provider.length),
      );
      expect(body, contains('jsonEncode(loaded.toJson())'));
    });
  });
}

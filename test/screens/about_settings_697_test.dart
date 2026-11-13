import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/settings/about_settings_screen.dart';

/// 697：关于页新增「联系方式」与「开源」分组。
///
/// ## 需求
///
/// 设置 → 关于 页需展示：
/// - 项目 GitHub 地址
/// - QQ 群号
/// - 联系邮箱
/// - 开源相关（第三方许可）
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String about;

  setUpAll(() => about = read('lib/screens/settings/about_settings_screen.dart'));

  group('1. 常量定义（单一事实源）', () {
    test('1.1 GitHub 地址正确', () {
      expect(AboutSettingsScreen.githubUrl,
          'https://github.com/JzeroM/himi-syncwatch');
    });

    test('1.2 QQ 群号正确', () {
      expect(AboutSettingsScreen.qqGroup, '1041283071');
    });

    test('1.3 邮箱正确', () {
      expect(AboutSettingsScreen.email, '2640256446jm@gmail.com');
    });
  });

  group('2. 联系方式分组', () {
    test('2.1 有「联系方式」分组标题', () {
      expect(about, contains("title: '联系方式'"));
    });

    test('2.2 三行都有稳定 key（测试可定位）', () {
      for (final k in const [
        'aboutGithub',
        'aboutQqGroup',
        'aboutEmail',
      ]) {
        expect(about, contains("ValueKey('$k')"), reason: '缺 $k');
      }
    });

    test('2.3 GitHub 行点击打开外部浏览器', () {
      final idx = about.indexOf("ValueKey('aboutGithub')");
      final block = about.substring(idx, idx + 500);
      expect(block, contains('AboutSettingsScreen.githubUrl'));
      expect(block, contains('_open('));
    });

    test('2.4 QQ 群行用 mqqapi 协议拉起客户端', () {
      expect(about, contains('mqqapi://card/show_pslcard'));
      expect(about, contains('uin='));
    });

    test('2.5 邮箱行用 mailto', () {
      expect(about, contains("'mailto:"));
    });

    test('2.6 打开失败给提示（不静默）', () {
      // launchUrl 返回 false 不抛异常，不提示会让用户以为点击无效
      final idx = about.indexOf('Future<void> _open(');
      final block = about.substring(idx, idx + 700);
      expect(block, contains('showAppToast'));
      expect(block, contains('无法打开'));
    });

    test('2.7 打开失败记日志', () {
      final idx = about.indexOf('Future<void> _open(');
      final block = about.substring(idx, idx + 700);
      expect(block, contains('LogService'));
    });
  });

  group('3. 开源分组', () {
    test('3.1 有「开源」分组标题', () {
      expect(about, contains("title: '开源'"));
    });

    test('3.2 有开源软件说明行', () {
      expect(about, contains('开源软件'));
      expect(about, contains('欢迎提交 Issue'));
    });

    test('3.3 第三方许可走 Flutter 内置页面', () {
      expect(about, contains('showLicensePage'));
      expect(about, contains("ValueKey('aboutThirdPartyLicenses')"));
    });

    test('3.4 许可页带应用名与版本', () {
      final idx = about.indexOf('showLicensePage');
      final block = about.substring(idx, idx + 400);
      expect(block, contains('applicationName'));
      expect(block, contains('applicationVersion'));
    });

    test('3.5 不链接不存在的 LICENSE 文件（避免 404）', () {
      // 项目当前没有 LICENSE 文件，指向它会是死链
      final hasLicenseFile = File('LICENSE').existsSync() ||
          File('LICENSE.md').existsSync();
      if (!hasLicenseFile) {
        expect(about, isNot(contains('blob/main/LICENSE')),
            reason: '无 LICENSE 文件时不应链接它');
      }
    });
  });

  group('4. 保持原有功能', () {
    test('4.1 版本分组仍在', () {
      expect(about, contains("title: '版本'"));
      expect(about, contains('HIMI 私密同步观影'));
    });

    test('4.2 更新分组仍在', () {
      expect(about, contains("title: '更新'"));
      expect(about, contains('检查更新'));
      expect(about, contains('新版本提醒'));
    });

    test('4.3 TV 遥控器适配（settingsTvWrapRow）', () {
      // 新增行必须走 settingsTvWrapRow，否则 TV 上无法用遥控器操作
      final code = codeOnly(about);
      final tvWraps = 'settingsTvWrapRow('.allMatches(code).length;
      expect(tvWraps, greaterThanOrEqualTo(4),
          reason: '更新 2 行 + 联系方式 3 行 + 许可 1 行');
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 656：分平台更新说明 + GitHub Release 说明同步。
///
/// ## 背景
///
/// 之前 Release 说明只有 `generate_release_notes: true` 生成的 commit 标题
/// 列表（如「fix(android): 655 删除两项自动检测」）。普通用户看不懂，
/// 也不知道「这个改动对我有什么影响」。
///
/// 而且一次发版通常只有部分平台有变更（比如 1.5.76 只改了 Windows 和
/// Android，鸿蒙无变化）——统一写一段会让人误以为所有端都变了。
///
/// ## 现在
///
/// `docs/release_notes_by_platform.md` 按平台分节，`release.yml` 提取
/// 三个章节拼进 Release body，同时保留自动 commit 列表（给开发者排查）。
void main() {
  const notesPath = 'docs/release_notes_by_platform.md';
  final notes = File(notesPath).readAsStringSync();
  final workflow =
      File('.github/workflows/release.yml').readAsStringSync();

  group('① 文档按平台分节', () {
    test('三个平台各有独立章节', () {
      expect(notes, contains('# Android 更新说明'));
      expect(notes, contains('# Windows 更新说明'));
      expect(notes, contains('# HarmonyOS 更新说明'));
    });

    test('每节标注适用版本（避免用户看历史 Release 时混淆）', () {
      final versions = RegExp(r'> 适用版本：\*\*v([0-9.]+)\*\*')
          .allMatches(notes)
          .map((m) => m.group(1))
          .toList();
      expect(versions.length, 3, reason: '三个平台各要标一次版本');
      expect(versions.every((v) => v == versions.first), isTrue,
          reason: '同一份文档里三个平台版本应一致');
    });

    test('文档版本与 pubspec 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version: ([0-9.]+)\+', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull);
      expect(notes, contains('**v${m!.group(1)}**'),
          reason: '发版时忘记更新文档版本会在这里被抓住');
    });
  });

  group('② 各平台内容对得上实际改动', () {
    test('Android 写明「自动回退删除」与三个手动开关', () {
      final android = _section(notes, 'Android');
      expect(android, contains('纹理'));
      expect(android, contains('Surface'));
      // 三个开关
      expect(android, contains('视频路径'));
      expect(android, contains('渲染器'));
      expect(android, contains('解码方式'));
      // 迁移说明（用户最关心）
      expect(android, contains('迁移'));
    });

    test('Windows 写明 Qt 播放器开关与 HDR 修复', () {
      final windows = _section(notes, 'Windows');
      expect(windows, contains('使用 Qt 播放器窗口'));
      expect(windows, contains('HDR'));
      expect(windows, contains('默认是关闭的'),
          reason: '必须明确告知默认关闭，否则用户以为坏了');
      // 控件清单
      expect(windows, contains('顶栏'));
      expect(windows, contains('底栏'));
      expect(windows, contains('快捷键'));
    });

    test('HarmonyOS 明确写「无变更」（而不是留空）', () {
      final ohos = _section(notes, 'HarmonyOS');
      expect(ohos, contains('无变更'));
      // 指明上次变更版本，方便追溯
      expect(ohos, contains('1.5.72'));
    });

    test('每节都给出「遇到问题怎么办」', () {
      final android = _section(notes, 'Android');
      expect(android, contains('黑屏'),
          reason: 'Android 必须给黑屏的手动排查步骤');
      final windows = _section(notes, 'Windows');
      expect(windows, contains('关掉'),
          reason: 'Windows 必须说明 Qt 播放器出问题怎么回退');
    });
  });

  group('③ release.yml 正确拼装', () {
    test('用 body_path 而非纯自动生成', () {
      expect(workflow, contains('body_path: release-notes.md'));
    });

    test('同时保留自动 commit 列表', () {
      expect(workflow, contains('generate_release_notes: true'));
    });

    test('提取三个平台章节（不能把 Android 删掉）', () {
      // 【实测踩过的坑】最初用 `sed '1,/^---$/d'` 去掉文件头，但文档里
      // 平台之间也有 `---`，结果 Android 整节被删。改用 awk 按标题匹配。
      expect(workflow, contains('awk'));
      expect(workflow, contains('Android|Windows|HarmonyOS'));
      expect(
        workflow,
        isNot(contains(r"sed -e '1,/^---$/d'")),
        reason: 'sed 按 --- 删会把 Android 节误删',
      );
    });

    test('提取失败时有兜底（整份拷贝）', () {
      expect(workflow, contains('未能从'));
      expect(workflow, contains(r'cp "$SRC" "$OUT"'));
    });

    test('拼装步骤在 Create Release 之前', () {
      final buildIdx = workflow.indexOf('拼装分平台 Release 说明');
      final releaseIdx = workflow.indexOf('Create GitHub Release');
      expect(buildIdx, greaterThan(-1));
      expect(releaseIdx, greaterThan(-1));
      expect(buildIdx, lessThan(releaseIdx),
          reason: '必须先拼好 body 再创建 Release');
    });
  });

  group('④ 实际提取结果验证', () {
    test('awk 规则能从文档中提取到三个平台标题', () {
      // 用 Dart 模拟 awk 的匹配规则，确保正则与脚本一致
      final re = RegExp(r'^# (Android|Windows|HarmonyOS) 更新说明', multiLine: true);
      final matches = re.allMatches(notes);
      expect(matches.length, 3);
    });

    test('文档里不含维护说明（会被发布出去，不该给用户看）', () {
      // 【踩过的坑】最初把「维护方式」写在文档里，会被 awk 提取进 Release。
      // 现在维护说明拆到 docs/release_notes_README.md，不参与发布。
      expect(notes, isNot(contains('维护方式')),
          reason: '维护说明应放 release_notes_README.md');
      // 第一个标题就是平台章节，没有前置内容
      final re = RegExp(r'^# (Android|Windows|HarmonyOS) 更新说明', multiLine: true);
      final firstMatch = re.firstMatch(notes);
      expect(firstMatch, isNotNull);
      expect(firstMatch!.start, 0,
          reason: '文档应以平台标题开头，否则头部内容会混进 Release');
    });
  });
}

/// 取出某个平台的章节内容（从它的标题到下一个平台标题之前）。
String _section(String doc, String platform) {
  final re = RegExp(r'^# (Android|Windows|HarmonyOS) 更新说明', multiLine: true);
  final matches = re.allMatches(doc).toList();
  final idx = matches.indexWhere((m) => m.group(1) == platform);
  expect(idx, greaterThanOrEqualTo(0), reason: '找不到 $platform 章节');
  final start = matches[idx].start;
  final end = idx + 1 < matches.length ? matches[idx + 1].start : doc.length;
  return doc.substring(start, end);
}

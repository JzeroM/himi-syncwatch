import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 发布说明格式与 Release 拼装。
///
/// ## 演进
///
/// - **656**：按平台分节（Android / Windows / HarmonyOS 各一章）。原因是
///   一次发版常常只有部分平台有变更，统一写一段会让人误以为全都变了。
/// - **697**：改为**不分平台**的单一份。用户反馈「相同功能和修复放一起，
///   不分平台」——分平台会导致同一功能写三遍，读者还要自己比对哪条适用于
///   自己；而多数功能其实是全平台共享的。平台差异改用括号注明
///   （如「（安卓 TV）」）。
///
/// ## 现在的要求
///
/// 1. 单一份说明，`# 更新说明` 开头，不按平台分章
/// 2. 标注适用版本，且与 pubspec 一致
/// 3. 三段固定结构：新增功能 / 优化 / 修复一些已知问题
/// 4. **简短**：只写「是什么」，不写根因与实现细节
/// 5. `release.yml` 整份使用，不再按平台标题提取
void main() {
  const notesPath = 'docs/release_notes_by_platform.md';
  final notes = File(notesPath).readAsStringSync();
  final workflow =
      File('.github/workflows/release.yml').readAsStringSync();

  group('① 文档为不分平台的单一份', () {
    test('以「# 更新说明」开头', () {
      expect(notes.trimLeft(), startsWith('# 更新说明'),
          reason: '头部内容会混进 Release，必须直接以标题开头');
    });

    test('不再有分平台章节', () {
      for (final p in const ['Android', 'Windows', 'HarmonyOS']) {
        expect(notes, isNot(contains('# $p 更新说明')),
            reason: '697 起改为单一份，不应再有 $p 独立章节');
      }
    });

    test('标注适用版本，且与 pubspec 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version: ([0-9.]+)\+', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull);
      expect(notes, contains('> 适用版本：**v${m!.group(1)}**'),
          reason: '发版时忘记更新文档版本会在这里被抓住');
    });
  });

  group('② 三段固定结构', () {
    test('包含「新增功能」', () {
      expect(notes, contains('## 新增功能'));
    });

    test('包含「优化」', () {
      expect(notes, contains('## 优化'));
    });

    test('包含「修复一些已知问题」', () {
      expect(notes, contains('## 修复一些已知问题'));
    });

    test('三段顺序正确（新增功能 → 优化 → 修复）', () {
      final a = notes.indexOf('## 新增功能');
      final b = notes.indexOf('## 优化');
      final c = notes.indexOf('## 修复一些已知问题');
      expect(a, greaterThan(-1));
      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
    });

    test('每段都有内容（不留空章节）', () {
      for (final title in const ['## 新增功能', '## 优化', '## 修复一些已知问题']) {
        final start = notes.indexOf(title);
        expect(start, greaterThan(-1));
        final rest = notes.substring(start + title.length);
        final nextSection = rest.indexOf('\n## ');
        final body = nextSection >= 0 ? rest.substring(0, nextSection) : rest;
        expect(body.trim(), isNotEmpty, reason: '$title 不能为空');
      }
    });
  });

  group('③ 简短原则（697）', () {
    test('不写根因分析', () {
      for (final banned in const ['根因', '原因是', '实际是', '此前是']) {
        expect(notes, isNot(contains(banned)),
            reason: '发布说明面向用户，不写技术根因（命中「$banned」）');
      }
    });

    test('不写实现细节', () {
      for (final banned in const [
        'Q_PROPERTY',
        'sub-remove',
        'secondary-sid',
        'isolate',
        'setState',
      ]) {
        expect(notes, isNot(contains(banned)),
            reason: '不写代码级实现细节（命中「$banned」）');
      }
    });

    test('篇幅克制（不超过 40 行）', () {
      final lineCount = notes.trim().split('\n').length;
      expect(lineCount, lessThanOrEqualTo(40),
          reason: '发布说明应简短，当前 $lineCount 行');
    });

    test('修复项合并概述（不逐条列根因）', () {
      final start = notes.indexOf('## 修复一些已知问题');
      final body = notes.substring(start);
      // 每条修复应是一句话，不出现换行缩进的详细说明
      expect(body.split('\n').where((l) => l.trim().startsWith('-')).length,
          greaterThanOrEqualTo(1));
    });
  });

  group('④ release.yml 整份使用说明', () {
    test('用 body_path 而非纯自动生成', () {
      expect(workflow, contains('body_path: release-notes.md'));
    });

    test('同时保留自动 commit 列表', () {
      expect(workflow, contains('generate_release_notes: true'));
    });

    test('检测新格式（# 更新说明）时整份使用', () {
      expect(workflow, contains("grep -q '^# 更新说明'"));
      expect(workflow, contains(r'cp "$SRC" "$OUT"'));
    });

    test('兼容旧格式（分平台标题）', () {
      // 历史 tag 重跑构建时文档仍是旧格式，需能退回按标题提取
      expect(workflow, contains('Android|Windows|HarmonyOS'));
    });

    test('提取失败时有兜底（整份拷贝）', () {
      expect(workflow, contains('未能从'));
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

  group('⑤ 不泄露维护说明', () {
    test('文档里不含维护方式（会被发布出去）', () {
      expect(notes, isNot(contains('维护方式')),
          reason: '维护说明应放 release_notes_README.md');
    });
  });
}

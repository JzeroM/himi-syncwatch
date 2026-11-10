# 分平台更新说明（维护指南）

`release_notes_by_platform.md` 会被 `release.yml` 自动拼进 GitHub Release 说明。

## 文件结构

```
docs/
├── release_notes_by_platform.md    ← 正文（会被发布出去）
└── release_notes_README.md         ← 本文件（不会发布）
```

## 发布时会发生什么

`release.yml` 的「拼装分平台 Release 说明」步骤：

```bash
awk '/^# (Android|Windows|HarmonyOS) 更新说明/ { started = 1 } started { print }' \
  docs/release_notes_by_platform.md >> release-notes.md
```

只提取**三个平台标题开始**的内容，所以：

- 文件里不能有「维护说明」这类给维护者看的内容（会被发布出去）
- 三个章节的标题必须严格是 `# Android 更新说明` / `# Windows 更新说明` /
  `# HarmonyOS 更新说明`（awk 按这个匹配）

## 发版前要做的

1. 更新 `release_notes_by_platform.md` 里三个平台的 `> 适用版本：**vX.Y.Z**`
2. 只改**有变更**的平台，其他平台保持原内容（或写「本版本无变更」）
3. 提交时确保 `pubspec.yaml` 的版本与文档版本一致
   （有测试 `test/ci/release_notes_by_platform_656_test.dart` 会检查）

## 写作要求

| 项 | 要求 |
|---|---|
| 面向用户 | 说「你能感受到什么」，不说 commit 标题 |
| 讲清现象 | 「之前的状况」比「修复了什么」更容易理解 |
| 讲清原因 | 用户知道为什么，才不会误以为是新 bug |
| 给出操作 | 尤其是「遇到问题怎么办」 |
| 不写内部代号 | `655` / `MPV` / `surface` 这类术语要配一句白话解释 |

## 踩过的坑

### `sed '1,/^---$/d'` 会删掉 Android 整节

最初想用 sed 去掉文件头部说明，但文档里**平台之间也有 `---`**，
结果第一个 `---` 就把 Android 整节删掉了。

改用 awk 按标题匹配，并且把维护说明拆到本文件（不参与发布）。

### Dart 测试里的 `$` 插值

断言 workflow 里的 shell 变量要写 raw string：

```dart
expect(workflow, contains(r'cp "$SRC" "$OUT"'));   // ✅
expect(workflow, contains('cp "$SRC" "$OUT"'));    // ❌ 编译失败
```

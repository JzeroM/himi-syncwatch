import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/log_service.dart';

/// 694：日志落盘加固与「导出全部」——
///
/// 真机回归：引擎切换闪退后导出的 himi_logs 只有启动段 5 行。两个根因：
/// 1. 异步批量缓冲没来得及落盘（native 崩溃丢最后一批）→ [LogService.flushSync]；
/// 2. 导出只写内存环 `_logs`（崩溃重启后只剩新会话）→ [LogService.collectFullLog]
///    改为导出跨会话的 himi_runtime.log 全量。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('log_service_persist_test');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('flushSync 把缓冲立即同步落盘（native 崩溃取证）', () async {
    final file = File('${tmp.path}/himi_runtime.log');
    LogService().debugAttachRuntimeFile(file);
    LogService().log('T1', 'sync-line-A', sync: true);
    // 同步写：无需等异步批量 flush，文件立即可见。
    expect(await file.readAsString(), contains('sync-line-A'));
  });

  test('非 sync 日志走异步批量，最终也会落盘', () async {
    final file = File('${tmp.path}/himi_runtime.log');
    LogService().debugAttachRuntimeFile(file);
    LogService().log('T1', 'async-line-B');
    // 异步批量（16ms 合帧）：等它落定。
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await file.readAsString(), contains('async-line-B'));
  });

  test('collectFullLog 导出全部：含历史会话（崩溃会话现场）', () async {
    final file = File('${tmp.path}/himi_runtime.log');
    // 模拟崩溃会话已落盘的现场（跨会话追加）。
    await file.writeAsString(
        '[00:00:00.000][Player] [rebuild] 5/7 创建新引擎\n'
        '[00:00:00.001][mpv] session created: native=true\n');
    LogService().debugAttachRuntimeFile(file);
    LogService().log('T2', 'current-session-line', sync: true);
    final all = await LogService().collectFullLog();
    // 崩溃会话 + 当前会话都要在。
    expect(all, contains('[rebuild] 5/7 创建新引擎'));
    expect(all, contains('session created: native=true'));
    expect(all, contains('current-session-line'));
  });

  test('collectFullLog 运行时文件不可用时退回内存环', () async {
    // 指向不存在的目录：文件永远建不出来。
    LogService().debugAttachRuntimeFile(File('${tmp.path}/nope/x.log'));
    LogService().log('T3', 'ring-only-line', sync: true);
    final all = await LogService().collectFullLog();
    expect(all, contains('ring-only-line'));
  });

  test('trimRuntimeFile 超限保尾、按行对齐、留裁剪标记', () async {
    final file = File('${tmp.path}/trim.log');
    final lines = List.generate(200, (i) => 'line-$i-内容测试');
    await file.writeAsString('${lines.join('\n')}\n');
    await LogService.trimRuntimeFile(file, maxBytes: 1000, keepBytes: 500);
    final content = await file.readAsString();
    // 尾部保留、头部裁掉。
    expect(content, contains('line-199-内容测试'));
    expect(content, isNot(contains('line-0-内容测试')));
    // 标记行 + 按行对齐（正文首行不是半行残缺）。
    final firstLine = content.split('\n').first;
    expect(firstLine, contains('裁剪'));
    final secondLine = content.split('\n')[1];
    expect(secondLine, startsWith('line-'));
  });

  test('trimRuntimeFile 未超限不动文件', () async {
    final file = File('${tmp.path}/trim_small.log');
    await file.writeAsString('keep-me\n');
    await LogService.trimRuntimeFile(file, maxBytes: 1000, keepBytes: 500);
    expect(await file.readAsString(), 'keep-me\n');
  });
}

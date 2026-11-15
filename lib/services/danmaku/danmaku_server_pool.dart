import 'dart:async';

/// 694 M4：多服务器并发执行 + 严格优先级仲裁（纯 Dart，可单测）。
///
/// 语义（对齐 NeoPlayer「N 个服务器并发搜索弹幕」，只抄思路）：
/// - [run] 按索引并发执行，索引即优先级（0 最高）；
/// - **严格优先级**：低优先级结果即使先到，也要等所有更高优先级
///   定局（未命中）后才采用；高优先级命中则立即返回（不被低优先级
///   挂起拖累）；
/// - 每源 [timeout] 超时按未命中（并发执行，总墙钟 ≈ 一次 timeout，
///   即「全局超时」语义）；
/// - 全部未命中/超时/无源 → 返回 null。
///
/// 返回胜者（优先级序号 + 结果）。
Future<({int index, R result})?> runDanmakuServers<R>({
  required int count,
  required Future<R?> Function(int index) run,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (count <= 0) return null;
  final done = List<bool>.filled(count, false);
  final res = List<R?>.filled(count, null);
  final completer = Completer<({int index, R result})?>();
  var pending = count;

  void settle() {
    if (completer.isCompleted) return;
    // 裁决：取「所有更高优先级均已定局」的最小索引命中。
    for (var j = 0; j < count; j++) {
      final r = res[j];
      if (r == null) continue;
      final higherAllDone = done.take(j).every((d) => d);
      if (higherAllDone) {
        completer.complete((index: j, result: r));
        return;
      }
    }
    if (pending == 0) completer.complete(null);
  }

  for (var i = 0; i < count; i++) {
    unawaited(() async {
      R? r;
      try {
        r = await run(i).timeout(timeout);
      } on TimeoutException {
        r = null; // 超时按未命中
      }
      res[i] = r;
      done[i] = true;
      pending--;
      settle();
    }());
  }
  return completer.future;
}

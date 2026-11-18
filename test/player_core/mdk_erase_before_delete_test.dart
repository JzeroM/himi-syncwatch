import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 694 真机回归（MDK→MPV 闪退，himi_logs(6) 钉死在 `mdk teardown: complete`
/// 之后、重启之前的窗口）——根因与修复守卫：
///
/// **根因**：Dart 用 `mdkPlayerAPI_new` 创建并用 `mdkPlayerAPI_delete` 删除
/// mdk player；Android `TexturePlayer` 非拥有包装（`owner_=false`），其析构
/// `~Player()→mdkPlayerAPI_reset(&p, false)`（注释 "reset callbacks, release
/// memory"）会对**存活 player** reset callbacks（触碰它）。所以触发
/// `~TexturePlayer` 的 **erase** 必须先于 `mdkPlayerAPI_delete`：
///   - texture 输出：`updateTexture(-1)→ReleaseRT` 同步 erase（delete 前）——安全。
///   - surfaceView 输出（**TV 默认**）：`updateTexture(-1)` 是 no-op（无 texId），
///     erase 靠 `FvpVideoView.dispose()/surfaceDestroyed`（Flutter 平台视图生命周期，
///     **异步、可能晚于 delete**）→ delete 后才 erase → reset 作用于已释放 player
///     → SIGSEGV。
///
/// **修复**：`disposeAsync` 在 `mdkPlayerAPI_delete` 前 `await detachPlayer(handle)`
/// 强制 erase（`nativeDetachPlayer` 按 handle 反查擦除，`~TexturePlayer` 在存活
/// player 上 reset），迟到的 `surfaceDestroyed` 查无此 player 走 "player not found"
/// 安全 no-op。
///
/// **取证**：delete 是 native 重操作，SIGSEGV 会丢异步批。用 `sync:true` 日志
/// （flushSync→writeAsStringSync，写内核页缓存、进程崩溃不丢）在 delete 前后各留
/// `MDK_DELETE_BEFORE/AFTER`，下次导出 himi_runtime.log 即知删除走到哪步。
void main() {
  final fvpPlayer =
      File('third_party/fvp/lib/src/player.dart').readAsStringSync();
  final fvpNative =
      File('third_party/fvp/android/fvp_plugin.cpp').readAsStringSync();
  final fvpJava = File('third_party/fvp/android/src/main/java/com/mediadevkit/fvp/FvpPlugin.java')
      .readAsStringSync();
  final adapter =
      File('lib/player_core/adapters/nipa_mdk_adapter.dart').readAsStringSync();

  String extractFun(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = start; i < src.length; i++) {
      if (src[i] == '{') {
        depth++;
        started = true;
      } else if (src[i] == '}') {
        depth--;
        if (started && depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  group('① erase-before-delete（UAF 根治：reset 必须作用于存活 player）', () {
    test('fvp disposeAsync 先 detachPlayer 再 mdkPlayerAPI_delete', () {
      final body = extractFun(fvpPlayer, 'Future<void> disposeAsync() async {');
      final detachIdx = body.indexOf('detachPlayer(nativeHandle)');
      final deleteIdx = body.indexOf('mdkPlayerAPI_delete(_pp)');
      expect(detachIdx, greaterThanOrEqualTo(0),
          reason: '必须在 delete 前强制 erase（surfaceView 输出的异步 erase 不可控）');
      expect(deleteIdx, greaterThanOrEqualTo(0), reason: '必须删除 player');
      expect(detachIdx, lessThan(deleteIdx),
          reason: 'erase-before-delete 顺序不得回退：'
              'delete 后 erase 会让 ~TexturePlayer 的 reset 作用于已释放 player → SIGSEGV');
    });

    test('nativeDetachPlayer 按 handle 擦除 players 表（触发 ~TexturePlayer）', () {
      expect(fvpNative, contains('Java_com_mediadevkit_fvp_FvpPlugin_nativeDetachPlayer'));
      expect(fvpNative, contains('players.erase(it)'),
          reason: 'erase 必须真删表项，才能让 ~TexturePlayer 在存活 player 上 reset');
      expect(fvpNative, contains('player->handleId == player_handle'),
          reason: '按 handle 反查（texture 用 texId、surfaceView 用 surfaceId，唯 handle 通用）');
    });

    test('TexturePlayer 记录 handleId 供反查', () {
      expect(fvpNative, contains('jlong handleId = 0;'));
      expect(fvpNative, contains('handleId = handle;'));
    });

    test('Java 侧 DetachPlayer 方法分发 + nativeDetachPlayer 声明', () {
      expect(fvpJava, contains('call.method.equals("DetachPlayer")'));
      expect(fvpJava, contains('nativeDetachPlayer(handle)'));
      expect(fvpJava, contains('static native void nativeDetachPlayer(long playerHandle)'));
    });
  });

  group('② 崩溃取证（sync:true 走 flushSync→writeAsStringSync，扛 native 闪退）', () {
    test('适配器在 delete 前后各打 sync:true 步标记', () {
      final body = extractFun(adapter, 'Future<void> _disposeAsyncInternal() async {');
      final beforeIdx = body.indexOf("'MDK_DELETE_BEFORE'");
      final afterIdx = body.indexOf("'MDK_DELETE_AFTER'");
      final disposeIdx = body.indexOf('_mdkPlayer.disposeAsync()');
      expect(beforeIdx, greaterThanOrEqualTo(0));
      expect(afterIdx, greaterThanOrEqualTo(0));
      expect(beforeIdx, lessThan(disposeIdx), reason: 'delete 前写 BEFORE');
      expect(disposeIdx, lessThan(afterIdx), reason: 'delete 返回后写 AFTER');
      // 两条标记都必须 sync:true（→flushSync 同步落盘，进程崩溃不丢）。
      expect(body, contains("'MDK_DELETE_BEFORE', sync: true"));
      expect(body, contains("'MDK_DELETE_AFTER', sync: true"));
    });
  });
}

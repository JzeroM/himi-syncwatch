import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 643：Windows 退出播放页闪退（`flutter_windows.dll` 0xc0000005 @ 0x1551f）。
///
/// 真机证据（事件查看器 + `himi_runtime.log` 双证）：
/// - 1.5.60.640 / 1.5.62.642 两次崩溃偏移**完全相同**；
/// - MPV / MDK / media_kit **三个引擎都崩**，偏移一致；
/// - 崩溃前连续出现 `Bad state: Future already completed`，堆栈指向
///   `main_shell.dart:71` 的 `_goBranch`。
///
/// 结论：崩溃点在 Flutter 引擎的路由/纹理清理路径，**与播放器引擎无关**。
/// 641「换引擎」无效正是因此。
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('① _goBranch 双重 pop（根因 A：侧边栏切 tab）', () {
    late String shell;

    setUp(() {
      shell = read('lib/screens/shell/main_shell.dart');
    });

    test('popUntil 前有 canPop 守卫（不再无条件退栈）', () {
      final start = shell.indexOf('void _goBranch(int index)');
      expect(start, greaterThan(-1));
      final body = shell.substring(start, start + 2200);

      expect(
        body,
        contains('nav.canPop()'),
        reason: '必须先用 canPop 判断，否则 goBranch 内部再退栈 → '
            '同一条路由 complete 两次 → Future already completed',
      );
      // 旧写法（无条件 ?.popUntil）不得残留。
      expect(
        body,
        isNot(contains('currentState?.popUntil((r) => r.isFirst)')),
        reason: '无条件 ?.popUntil 是双重 pop 的来源',
      );
    });

    test('canPop 守卫在 popUntil 之前', () {
      final start = shell.indexOf('void _goBranch(int index)');
      final body = shell.substring(start, start + 2200);
      final guardIdx = body.indexOf('nav.canPop()');
      final popIdx = body.indexOf('nav.popUntil');
      expect(guardIdx, greaterThan(-1));
      expect(popIdx, greaterThan(guardIdx));
    });

    test('goBranch 仍在守卫之外调用（切 tab 本身不能丢）', () {
      final start = shell.indexOf('void _goBranch(int index)');
      final body = shell.substring(start, start + 2200);
      final popIdx = body.indexOf('nav.popUntil');
      // 用 lastIndexOf：注释里也提到了 `widget.shell.goBranch(...)`，
      // 实际调用在守卫块之后。
      final goIdx = body.lastIndexOf('widget.shell.goBranch');
      expect(goIdx, greaterThan(popIdx));
    });
  });

  group('② 播放页安全退出（根因 B：dispose 与纹理注销竞态）', () {
    late String screen;

    setUp(() {
      screen = read('lib/screens/player/player_screen.dart');
    });

    test('新增 _videoLayerDetached 标志', () {
      expect(screen, contains('bool _videoLayerDetached = false'));
    });

    test('build 里按标志短路视频层（不再挂 Texture）', () {
      expect(screen, contains('final videoContent = _videoLayerDetached'));
      expect(screen, contains('const SizedBox.shrink()'));
    });

    test('_safePopPlayerPage 顺序：卸层 → endOfFrame → 50ms → pop', () {
      final start = screen.indexOf('Future<void> _safePopPlayerPage(');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 1600);

      final setIdx = body.indexOf('_videoLayerDetached = true');
      final frameIdx = body.indexOf('WidgetsBinding.instance.endOfFrame');
      final delayIdx = body.indexOf('Duration(milliseconds: 50)');
      final popIdx = body.indexOf('Navigator.pop(context)');

      expect(setIdx, greaterThan(-1), reason: '必须先卸视频层');
      expect(frameIdx, greaterThan(setIdx), reason: '卸层后要等一帧');
      expect(delayIdx, greaterThan(frameIdx), reason: '一帧后再补 50ms');
      expect(popIdx, greaterThan(delayIdx), reason: '最后才 pop');
    });

    test('_safePopPlayerPage 支持 popUntilFirst（房间解散场景）', () {
      final start = screen.indexOf('Future<void> _safePopPlayerPage(');
      final body = screen.substring(start, start + 1600);
      expect(body, contains('popUntilFirst'));
      expect(body, contains('popUntil((route) => route.isFirst)'));
    });

    test('顶栏返回走 _safePopPlayerPage', () {
      final idx = screen.indexOf('onBack: () async {');
      expect(idx, greaterThan(-1));
      final body = screen.substring(idx, idx + 400);
      expect(body, contains('_safePopPlayerPage()'));
      expect(
        body,
        isNot(contains('Navigator.pop(context)')),
        reason: '顶栏返回不得直接 pop（会重现纹理竞态）',
      );
    });

    test('遥控返回键确认走 _safePopPlayerPage', () {
      final idx = screen.indexOf('onConfirm: () async {');
      expect(idx, greaterThan(-1));
      final body = screen.substring(idx, idx + 400);
      expect(body, contains('_safePopPlayerPage()'));
    });

    test('房间解散走 _safePopPlayerPage(popUntilFirst: true)', () {
      expect(
        screen,
        contains('_safePopPlayerPage(popUntilFirst: true)'),
        reason: '房间解散需一次退回根路由，但同样要先卸视频层',
      );
    });

    test('原生 UI 关闭退出走 _safePopPlayerPage', () {
      // closeNativeUi 之后不得再直接 pop。
      final idx = screen.indexOf('await mpv.closeNativeUi();');
      expect(idx, greaterThan(-1));
      final body = screen.substring(idx, idx + 600);
      expect(body, contains('_safePopPlayerPage()'));
      expect(body, isNot(contains('Navigator.pop(context)')));
    });

    test('dispose 用 try/finally 保证 super.dispose 执行', () {
      final idx = screen.indexOf('unawaited(_disposePlayerAfterDelay(player));');
      expect(idx, greaterThan(-1));
      // 往前找 try，往后找 finally。
      final before = screen.substring(idx - 200, idx);
      final after = screen.substring(idx, idx + 200);
      expect(before, contains('try {'), reason: 'unawaited 必须在 try 内');
      expect(after, contains('finally {'), reason: '必须有 finally');
      expect(after, contains('super.dispose()'));
    });

    test('Windows 全引擎都不延迟（修正 639 只覆盖 MPV）', () {
      final idx = screen.indexOf('Future<void> _disposePlayerAfterDelay(');
      expect(idx, greaterThan(-1));
      final body = screen.substring(idx, idx + 1800);
      expect(
        body,
        contains('if (defaultTargetPlatform != TargetPlatform.windows)'),
        reason: 'MDK 在 Windows 上也不得延迟（旧实现只跳过 MPV，反而更危险）',
      );
      expect(
        body,
        isNot(contains('isWindowsMpv')),
        reason: '按引擎特判已移除——时序统一由 _safePopPlayerPage 保证',
      );
    });
  });

  group('③ 日志同步落盘（保证崩溃现场可取证）', () {
    late String logService;

    setUp(() {
      logService = read('lib/services/log_service.dart');
    });

    test('682：落盘改为异步批量（同步 fsync 会卡死 UI 线程）', () {
      // 【643 → 682 的结论反转】
      // 643 当时改成 `writeAsStringSync(flush: true)` 是为了「崩溃现场
      // 必定可取证」。但真机证明：房间拖动窗口时 Qt 每 80ms 回一帧
      // `windowMoved`，Dart 跟随 + setBounds 连带多次日志 → 主线程
      // 上排队 fsync → 秒级卡死 → Windows 判定 Application Hang
      //（「进房间时 / 单人移动播放器窗口时无响应」）。
      //
      // 现在：内存缓冲 + 单飞异步 flush。主线程永不做同步 IO。
      //
      // 判定前剔除注释行——注释里会提到旧写法（说明为什么改）。
      final code = logService
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('*');
          })
          .join('\n');
      expect(code, isNot(contains('writeAsStringSync')));
      expect(code, contains('_runtimeBuffer.add(entry)'));
      expect(code, contains('_runtimeFlushing'));
      expect(code, contains('Future<void>.delayed'));
    });

    test('文件就绪前的日志先缓存，就绪后补写', () {
      // 682：启动早期（`_runtimeFile` 还是 null）的日志并入同一缓冲，
      // 就绪后由 `_initRuntimeFile` 触发一次批量写。
      expect(logService, contains('_runtimeBuffer'));
      expect(logService, contains('_runtimeBuffer.add(entry)'));
      expect(logService, contains('batch.join'));
    });
  });
}

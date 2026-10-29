import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart';

/// Android surface 仲裁回归（v1.5.4 黑屏修复）。
///
/// 真机故障序列：PlayerScreen 先挂 Flutter 平台视图（surface 101）→
/// 原生 UI Dialog 的 SurfaceView 出 surface 202 → 平台视图卸载销毁
/// surface 101。旧实现把「销毁 101」当成当前 surface 拆掉播放器，之后
/// 再无 surface 事件 → 解码正常但黑屏。
void main() {
  const policy = SurfaceRebindPolicy();

  group('SurfaceRebindPolicy.plan（surface 事件）', () {
    test('首绑：无播放器 + 新 handle → ensurePlayer', () {
      expect(
        policy.plan(currentHandle: 0, newHandle: 101, playerAlive: false),
        SurfaceAction.ensurePlayer,
      );
    });

    test('重复事件（同 handle 且已在播）→ none', () {
      expect(
        policy.plan(currentHandle: 101, newHandle: 101, playerAlive: true),
        SurfaceAction.none,
      );
    });

    test('原生 UI 抢占：播放器存活且 handle 变化 → rebind', () {
      expect(
        policy.plan(currentHandle: 101, newHandle: 202, playerAlive: true),
        SurfaceAction.rebind,
      );
    });

    test('播放器已销毁后新 surface → ensurePlayer（不是 rebind）', () {
      expect(
        policy.plan(currentHandle: 0, newHandle: 202, playerAlive: false),
        SurfaceAction.ensurePlayer,
      );
    });

    test('非法 handle（<=0）→ none', () {
      expect(
        policy.plan(currentHandle: 101, newHandle: 0, playerAlive: true),
        SurfaceAction.none,
      );
    });
  });

  group('SurfaceRebindPolicy.onDestroyed（销毁事件）', () {
    test('旧宿主销毁（非当前 handle）→ none，不能拆新 surface', () {
      expect(
        policy.onDestroyed(
          currentHandle: 202,
          destroyedHandle: 101,
          playerAlive: true,
        ),
        SurfaceAction.none,
      );
    });

    test('当前 surface 销毁 → detach', () {
      expect(
        policy.onDestroyed(
          currentHandle: 101,
          destroyedHandle: 101,
          playerAlive: true,
        ),
        SurfaceAction.detach,
      );
    });

    test('老包发 handle=0（未知）→ 保守 detach', () {
      expect(
        policy.onDestroyed(
          currentHandle: 101,
          destroyedHandle: 0,
          playerAlive: true,
        ),
        SurfaceAction.detach,
      );
    });

    test('无播放器且无绑定 surface 时的销毁 → none（幂等）', () {
      expect(
        policy.onDestroyed(
          currentHandle: 0,
          destroyedHandle: 0,
          playerAlive: false,
        ),
        SurfaceAction.none,
      );
    });
  });

  group('真机故障序列回放', () {
    test('平台视图 101 → Dialog 202 → 平台视图销毁 101：播放器存活', () {
      var handle = 0;
      var playerAlive = false;

      // 1. 平台视图 surface 101 到达。
      var action = policy.plan(
          currentHandle: handle, newHandle: 101, playerAlive: playerAlive);
      expect(action, SurfaceAction.ensurePlayer);
      handle = 101;
      playerAlive = true;

      // 2. 原生 UI Dialog surface 202 到达 → 换绑。
      action = policy.plan(
          currentHandle: handle, newHandle: 202, playerAlive: playerAlive);
      expect(action, SurfaceAction.rebind);
      handle = 202;

      // 3. 平台视图销毁（101）→ 忽略，播放器继续绑在 202 上。
      action = policy.onDestroyed(
          currentHandle: handle, destroyedHandle: 101, playerAlive: true);
      expect(action, SurfaceAction.none);
    });

    test('关闭原生 UI：Dialog 销毁 202 → detach → 平台视图重建 101', () {
      var handle = 202;
      var playerAlive = true;

      var action = policy.onDestroyed(
          currentHandle: handle, destroyedHandle: 202, playerAlive: true);
      expect(action, SurfaceAction.detach);
      handle = 0;
      playerAlive = false;

      action = policy.plan(
          currentHandle: handle, newHandle: 101, playerAlive: playerAlive);
      expect(action, SurfaceAction.ensurePlayer);
    });
  });
}

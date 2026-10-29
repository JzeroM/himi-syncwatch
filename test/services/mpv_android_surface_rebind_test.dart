import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart';

/// Android surface 仲裁回归（v1.5.4 黑屏修复）。
///
/// 真机故障序列：
/// 1. PlayerScreen 先挂 Flutter 平台视图（surface 101，src=platform）；
/// 2. 原生 UI Dialog 打开，其 SurfaceView 出 surface 202（src=native）；
/// 3. 平台视图卸载：`surfaceChanged` 可能把 101 再发一次（抢回绑定），
///    随后 `dispose()` 若不发销毁事件，Dart 永远不知道 101 已死
///    → mpv 搁浅在死 surface → 硬解失败、`video-params` 永不到来 → 黑屏。
void main() {
  const policy = SurfaceRebindPolicy();

  group('SurfaceRebindPolicy.accept（来源过滤）', () {
    test('原生 UI 接管中只接受 native 事件', () {
      expect(
        policy.accept(nativeUiActive: true, eventSrc: SurfaceSrc.nativeUi),
        isTrue,
      );
      expect(
        policy.accept(nativeUiActive: true, eventSrc: SurfaceSrc.platform),
        isFalse,
      );
    });

    test('未接管只接受 platform 事件', () {
      expect(
        policy.accept(nativeUiActive: false, eventSrc: SurfaceSrc.platform),
        isTrue,
      );
      expect(
        policy.accept(nativeUiActive: false, eventSrc: SurfaceSrc.nativeUi),
        isFalse,
      );
    });

    test('老包无 src 字段 → 放行（无法仲裁，保持旧行为）', () {
      expect(policy.accept(nativeUiActive: true, eventSrc: null), isTrue);
      expect(policy.accept(nativeUiActive: false, eventSrc: null), isTrue);
    });
  });

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

      // 1. 平台视图 surface 101 到达（未接管，src=platform）。
      expect(
        policy.accept(nativeUiActive: false, eventSrc: SurfaceSrc.platform),
        isTrue,
      );
      var action = policy.plan(
          currentHandle: handle, newHandle: 101, playerAlive: playerAlive);
      expect(action, SurfaceAction.ensurePlayer);
      handle = 101;
      playerAlive = true;

      // 2. 原生 UI 接管，Dialog surface 202 到达 → 换绑。
      expect(
        policy.accept(nativeUiActive: true, eventSrc: SurfaceSrc.nativeUi),
        isTrue,
      );
      action = policy.plan(
          currentHandle: handle, newHandle: 202, playerAlive: playerAlive);
      expect(action, SurfaceAction.rebind);
      handle = 202;

      // 3. 垂死平台视图再发 101 → 来源被过滤，绝不抢回绑定。
      expect(
        policy.accept(nativeUiActive: true, eventSrc: SurfaceSrc.platform),
        isFalse,
      );
    });

    test('平台视图 dispose 发 destroyed(101) → 非当前 handle，忽略', () {
      // 即使老逻辑漏过滤，销毁事件也不会拆掉 native 上正在播的播放器。
      expect(
        policy.onDestroyed(
          currentHandle: 202,
          destroyedHandle: 101,
          playerAlive: true,
        ),
        SurfaceAction.none,
      );
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

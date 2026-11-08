import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

/// 591：手势方向修正 + 房间面板推送时机。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final playerScreen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('手势方向：上滑增大（Android distanceY 正值 = 上滑）', () {
    test('安卓不再取负号', () {
      // 旧实现 `(-distanceY / VERTICAL_PX_PER_FULL)` 把方向弄反：
      // Android GestureDetector.onScroll 的 distanceY 正值就是手指上滑，
      // 取负后变成「上滑减小」。
      expect(kotlinScreen, contains('(distanceY / VERTICAL_PX_PER_FULL)'));
      expect(
        kotlinScreen,
        isNot(contains('(-distanceY / VERTICAL_PX_PER_FULL)')),
        reason: '旧实现的取负号会让方向反过来',
      );
    });

    test('Flutter 参考实现语义（primaryDelta 上滑为负 → 减去后增大）', () {
      expect(playerScreen, contains('_brightness = (_brightness - delta / 600)'));
    });

    test('鸿蒙 offsetY 下滑为正 → 取负后下滑减小（方向正确）', () {
      expect(ohosView, contains('const delta01 = -totalDy / 600;'));
    });
  });

  group('手势方向锁：斜向拖动不得中途切轴', () {
    test('安卓 dragAxis 一次性定轴', () {
      expect(kotlinScreen, contains('private var dragAxis: Int = AXIS_NONE'));
      expect(kotlinScreen, contains('if (dragAxis == AXIS_NONE) {'));
      expect(kotlinScreen,
          contains('dragAxis =\n                        if (Math.abs(dx) > Math.abs(dy)) AXIS_HORIZONTAL else AXIS_VERTICAL'));
      // 定轴后分派（不再每帧重判）。
      expect(kotlinScreen, contains('if (dragAxis == AXIS_HORIZONTAL) {'));
    });

    test('ACTION_DOWN 复位方向锁', () {
      expect(kotlinScreen, contains('dragAxis = AXIS_NONE'));
    });

    test('横拖累加器只在横向锁定时提交（ACTION_UP + onFling 双守卫）', () {
      expect(kotlinScreen, contains('if (dragAxis == AXIS_HORIZONTAL &&'));
      expect(kotlinScreen, contains('if (dragAxis != AXIS_HORIZONTAL) return false'));
    });

    test('鸿蒙同款方向锁 + onPanEnd 守卫', () {
      expect(ohosView, contains('private dragAxis: number = 0;'));
      expect(ohosView, contains('this.dragAxis = Math.abs(totalDx) > Math.abs(totalDy) ? 1 : 2;'));
      expect(ohosView, contains('if (this.dragAxis !== 1 || Math.abs(this.hDragAccumPx) < 10)'));
    });
  });

  group('纵拖分区：左亮度 / 右音量（与 Flutter 一致）', () {
    test('安卓按 dragOnLeftSide 分派', () {
      expect(kotlinScreen, contains('if (dragOnLeftSide) {'));
      expect(kotlinScreen, contains('listener?.onGestureBrightness(delta01)'));
      expect(kotlinScreen, contains('listener?.onGestureVolumeDelta(delta01)'));
    });

    test('DOWN 时按半屏宽判定侧别', () {
      expect(kotlinScreen, contains('dragOnLeftSide = event.x < width / 2f'));
    });
  });

  group('在线人数：RTM 返回 0 不覆盖（保留至少 1）', () {
    test('resolveOnlineCount 边界', () {
      // RTM 权威值 > 0 → 采用。
      expect(PlayerScreen.resolveOnlineCount(current: 1, rtmCount: 3), 3);
      expect(PlayerScreen.resolveOnlineCount(current: 5, rtmCount: 2), 2);
      // RTM 未同步返回 0 → 保留当前值。
      expect(PlayerScreen.resolveOnlineCount(current: 2, rtmCount: 0), 2);
      expect(PlayerScreen.resolveOnlineCount(current: 1, rtmCount: 0), 1);
      // 当前值也非法时兜底 1（房间里至少有自己）。
      expect(PlayerScreen.resolveOnlineCount(current: 0, rtmCount: 0), 1);
      expect(PlayerScreen.resolveOnlineCount(current: -1, rtmCount: 0), 1);
    });

    test('639：_refreshOnlineCount 改用成员集合（不再用 resolveOnlineCount）', () {
      // 真机回归「观众退房人数未减」：resolveOnlineCount 在 rtmCount==0 时
      // 保留旧值 → 人数永不下降。改为事件驱动的成员集合 + ids 校准。
      // resolveOnlineCount 纯函数本身保留（边界测试仍有效），但主路径不再用。
      final body = playerScreen.substring(
        playerScreen.indexOf('void _refreshOnlineCount('),
      );
      final head = body.substring(0, body.indexOf('\n  }'));
      // 去注释后再断言，避免注释里提到旧实现被误判。
      final code = head
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i >= 0 ? l.substring(0, i) : l;
          })
          .join('\n');
      expect(code, contains('getOnlineUserIds'));
      expect(code, contains('_applyOnlineUsers'));
      expect(code, isNot(contains('resolveOnlineCount')));
    });
  });

  group('房间面板推送时机（真机「资源面板全空、播报 0」根因）', () {
    test('_addBroadcastMessage 推原生', () {
      final idx = playerScreen.indexOf('void _addBroadcastMessage(String msg)');
      expect(idx, greaterThan(0));
      final body = playerScreen.substring(idx, idx + 700);
      expect(body, contains('_syncNativePanelData()'));
    });

    test('_refreshOnlineCount 推原生', () {
      final idx = playerScreen.indexOf('void _refreshOnlineCount(RtmService rtmService)');
      expect(idx, greaterThan(0));
      final body = playerScreen.substring(idx, idx + 800);
      expect(body, contains('_syncNativePanelData()'));
    });

    test('_applyRoomResources 兜底推原生（无剧集列表也推）', () {
      final idx = playerScreen.indexOf("_addBroadcastMessage('已同步房间资源列表')");
      expect(idx, greaterThan(0));
      final body = playerScreen.substring(idx, idx + 400);
      expect(body, contains('_syncNativePanelData()'));
      expect(body, contains('无论是否有剧集列表'));
    });
  });

  group('ToggleRoomSync 命令接线（此前静默丢弃）', () {
    test('播放页有 case 分支', () {
      expect(playerScreen, contains('case ToggleRoomSync():'));
      expect(playerScreen, contains('_setupRoomSync()'));
    });
  });

  group('安卓资源面板头部布局', () {
    test('标题 ellipsize + 后续控件固定宽（不再把三者挤到最右）', () {
      expect(kotlinScreen, contains('roomPanelTitle.ellipsize = TextUtils.TruncateAt.END'));
      // 搜索 28dp、人数/角色按 wrap_content。
      expect(kotlinScreen, contains('roomPanelHeader.addView(roomPanelSearch, llp(dp(28), dp(28), 12))'));
    });
  });
}

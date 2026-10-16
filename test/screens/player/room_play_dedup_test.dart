import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

/// 观众起播去重（v1.2.7 修 HDR 房间观众黑屏）。
///
/// 房主 `join` 处理先发带 playUrl 的 roomInfo、再发同 URL 的 syncPlay；
/// 流为空时 requestRoomInfo 响应还会再带一次。同一 URL 重复触发会让观众
/// 并发执行 media=/prepare/纹理/引擎重建 → 竞态黑屏。该纯函数决定是否起播。
void main() {
  group('PlayerScreen.shouldStartAudiencePlay', () {
    const urlA = 'https://emby/stream?A';
    const urlB = 'https://emby/stream?B';

    test('首次收到 playUrl（当前为空）→ 起播', () {
      expect(
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: urlA,
          currentPlayUrl: '',
          inFlightPlayUrl: null,
        ),
        isTrue,
      );
    });

    test('roomInfo 已起播后 syncPlay 同 URL → 跳过（去重）', () {
      expect(
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: urlA,
          currentPlayUrl: urlA,
          inFlightPlayUrl: null,
        ),
        isFalse,
        reason: '房主 join 路径 roomInfo 先到并同步写入 _currentPlayUrl，'
            'syncPlay 同 URL 必须被拦截',
      );
    });

    test('同 URL 已有在飞起播 → 跳过（并发单飞）', () {
      expect(
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: urlA,
          currentPlayUrl: '', // 尚未写入（并发窗口）
          inFlightPlayUrl: urlA,
        ),
        isFalse,
        reason: '两条同 URL 并发（roomInfo+syncPlay）必须只放行一条',
      );
    });

    test('切集：不同 URL → 起播', () {
      expect(
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: urlB,
          currentPlayUrl: urlA,
          inFlightPlayUrl: null,
        ),
        isTrue,
      );
    });

    test('空 URL → 不起播', () {
      expect(
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: '',
          currentPlayUrl: '',
          inFlightPlayUrl: null,
        ),
        isFalse,
      );
    });

    test('房主 join 完整序列（roomInfo(A) → syncPlay(A) → retry roomInfo(A)）'
        '仅首次起播', () {
      var currentPlayUrl = '';
      var inFlight = '';
      bool decide(String url) => PlayerScreen.shouldStartAudiencePlay(
            playUrl: url,
            currentPlayUrl: currentPlayUrl,
            inFlightPlayUrl: inFlight.isEmpty ? null : inFlight,
          );

      // ① roomInfo(A)：放行，入口同步写入 current 与在飞。
      expect(decide(urlA), isTrue);
      currentPlayUrl = urlA;
      inFlight = urlA;
      // ② 起播完成，在飞清空。
      inFlight = '';
      // ③ syncPlay(A)：同 URL → 拦截。
      expect(decide(urlA), isFalse);
      // ④ retry roomInfo(A) 响应：同 URL → 拦截。
      expect(decide(urlA), isFalse);
    });
  });
}

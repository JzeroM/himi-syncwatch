import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 619：弹幕加载加速 + 安卓弹幕抽搐修复。
///
/// 两个独立问题：
/// ① 弹幕「出现太慢」——`withRelated=true` 触发服务端实时聚合（实测同一
///    episodeId 首次 12.15s vs 1.05s，而响应体 MD5 完全相同）；
///    字幕组命名导致 match 0 命中 → 落到 105 候选的 search 串行。
/// ② 安卓弹幕「抽搐」——`setClock` 无条件重设 `snapAtMs`，而它被本地
///    500ms tick 用同一份旧快照重复调用 → 位置回退 150ms 再跳回。
void main() {
  final client = File(
    'lib/services/danmaku/dandanplay_client.dart',
  ).readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final danmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① 去掉 withRelated（最大单点收益）', () {
    test('fetchComments 不再带 withRelated 参数', () {
      final body = bodyOf(
        client,
        'Future<List<DanmakuComment>> fetchComments(int episodeId) async {',
      );
      // 实际请求参数里不能出现 withRelated（注释里保留根因说明是允许的）。
      expect(body, isNot(contains("'withRelated'")));
      expect(body, isNot(contains('withRelated: ')));
      // 仍保留 format=json（danmu_api 显式格式参数）。
      expect(body, contains("'format': 'json'"));
    });

    test('注释记录「响应体 MD5 相同、纯延迟」的实测结论', () {
      expect(client, contains('MD5 完全相同'));
      expect(client, contains('12.15s'));
      expect(client, contains('1.05s'));
    });
  });

  group('② 剧名+集号重试 match（跳过 search 兜底）', () {
    test('存在 _danmakuSeriesMatchFileName', () {
      expect(screen, contains('String? _danmakuSeriesMatchFileName()'));
    });

    test('用 DanmakuMatcher.fromEpisode 生成剧名.SxxExx', () {
      final body = bodyOf(screen, 'String? _danmakuSeriesMatchFileName() {');
      expect(body, contains('DanmakuMatcher.fromEpisode'));
      expect(body, contains('seriesName: series'));
      expect(body, contains('season: ep.season'));
      expect(body, contains('number: ep.number'));
      // 非剧集（season/number <= 0）返回 null。
      expect(body, contains('ep.season <= 0 || ep.number <= 0'));
    });

    test('match 空结果时用 seriesFileName 重试', () {
      final idx =
          screen.indexOf('Future<void> _loadDanmaku({bool force = false}) async {');
      expect(idx, greaterThan(0));
      final end = screen.indexOf('/// 失败统一处理', idx);
      final body = screen.substring(idx, end);
      expect(body, contains('if (matched.isEmpty)'));
      expect(body, contains('_danmakuSeriesMatchFileName()'));
      expect(
        body,
        contains('matched = await client.match(fileName: seriesFileName)'),
      );
    });
  });

  group('③ 候选上限 12（串行，不并行）', () {
    test('常量定义存在且为 12', () {
      expect(screen, contains('static const int maxDanmakuCandidates = 12;'));
    });

    test('_tryDanmakuCandidates 调用处 take 上限', () {
      expect(screen, contains('.take(PlayerScreen.maxDanmakuCandidates)'));
    });

    test('不引入候选并行 fetch（实测并行收益有限、曾触发 429）', () {
      final body = bodyOf(
        screen,
        'Future<({int id, List<DanmakuComment> comments})?> _tryDanmakuCandidates(',
      );
      // 候选之间必须串行（for 循环内 await），不得 Future.wait 并发。
      expect(body, contains('for (final id in ids)'));
      expect(body, isNot(contains('Future.wait')));
    });
  });

  group('④ 安卓弹幕抽搐：setClock 值去重', () {
    test('存在去重字段（位置/暂停/倍速三元组）', () {
      expect(danmaku, contains('private var lastClockPosMs = Long.MIN_VALUE'));
      expect(danmaku, contains('private var lastClockPaused = true'));
      expect(danmaku, contains('private var lastClockSpeed = 1.0'));
    });

    test('输入不变时直接返回，不重锚', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('val sameInput = positionMs == lastClockPosMs'));
      expect(body, contains('paused == lastClockPaused'));
      expect(body, contains('speed == lastClockSpeed'));
      expect(body, contains('if (sameInput)'));
      // 去重分支只补时长，不动 snapPosMs / snapAtMs。
      expect(body, contains('snapDurationMs = durationMs'));
      expect(body, contains('return'));
    });

    test('去重后才更新快照与锚点', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('lastClockPosMs = positionMs'));
      expect(body, contains('snapPosMs = positionMs'));
      expect(body, contains('snapAtMs = System.currentTimeMillis()'));
    });

    test('注释记录「本地 tick 用旧快照重锚 → 回退 150ms」根因', () {
      expect(danmaku, contains('619 真机回归：安卓弹幕仍然抽搐'));
      expect(danmaku, contains('回退 150ms'));
      expect(danmaku, contains('ValueNotifier'));
    });
  });

  group('⑥ 全平台/全引擎/全模式覆盖（共用唯一入口）', () {
    test('弹幕 API 客户端唯一（与引擎无关，故 ①② 天然全覆盖）', () {
      // 全仓只有 PlayerScreen 持有 DandanplayClient，无引擎分支。
      final hits = <String>[];
      for (final f in [
        'lib/screens/player/player_screen.dart',
        'lib/services/player/mpv_player_adapter.dart',
        'lib/services/player/mdk_player_adapter.dart',
        'lib/services/player/erika_player_adapter.dart',
      ]) {
        final src = File(f).readAsStringSync();
        if (src.contains('DandanplayClient(')) hits.add(f);
      }
      expect(hits, ['lib/screens/player/player_screen.dart']);
    });

    test('加载入口唯一（房间/同步起播/手动开关均走 _loadDanmaku）', () {
      final loads = '_loadDanmaku'.allMatches(screen).length;
      // 定义 1 + 触发点若干；关键是**没有第二套加载实现**。
      expect(loads, greaterThan(3));
      expect(screen, isNot(contains('_loadDanmakuLegacy')));
      expect(screen, isNot(contains('_fetchDanmakuDirect')));
      // 房间/同步起播路径的注释已明确覆盖。
      expect(screen, contains('覆盖房间/同步起播路径'));
    });

    test('三条渲染路径的值去重均有保障', () {
      // ① Flutter（MDK/media_kit/Windows）：ValueNotifier 值去重。
      final overlay =
          File('lib/screens/player/widgets/danmaku_overlay.dart').readAsStringSync();
      expect(overlay, contains('widget.position.addListener'));
      expect(overlay, contains('_onPositionChanged'));
      // ② 安卓原生：619 新增显式去重。
      expect(danmaku, contains('val sameInput = positionMs == lastClockPosMs'));
      // ③ 鸿蒙原生：positionNowMs 为纯函数（无自维护锚点）。
      final ohosHost = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiMpvNativeHost.ets',
      ).readAsStringSync();
      expect(ohosHost, contains('positionNowMs(): number'));
      expect(ohosHost, contains('Date.now() - this.lastStateAtMs'));
      // 鸿蒙弹幕层不自维护锚点（直接读宿主纯函数）。
      final ohosLayer = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(ohosLayer, contains('positionNowMs()'));
      expect(ohosLayer, isNot(contains('anchorPosMs')));
    });

    test('Windows 646 起也走原生 UI（顶层窗口 + 原生弹幕层）', () {
      final gating = File(
        'lib/services/player/native/native_player_gating.dart',
      ).readAsStringSync();
      // 646：Windows 加入原生 UI 平台——HDR 直出走独立 WS_POPUP 顶层窗口
      // （子 HWND 会被 Flutter 的 DirectComposition 遮挡），弹幕随之改由
      // 原生层绘制（阶段 5）。
      expect(gating, contains("'android'"));
      expect(gating, contains("'ohos'"));
      expect(gating, contains("'windows'"));
    });

    test('Erika 用引擎内部合成（不在本仓，故不适用）', () {
      expect(screen, contains('_currentEngine != PlayerEngine.erika'));
      expect(screen, contains('ErikaDanmakuPlayer'));
    });
  });

  group('⑤ track-list 空表不再刷日志（619 噪音修复）', () {
    test('只在「有轨道但解析不出 id」时才报警', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains('hasRawTracks'));
      expect(body, contains('if (hasRawTracks)'));
      // 旧的「空表也报警」文案已改。
      expect(body, isNot(contains('track-list 解析无结果（结构不符？）')));
      expect(body, contains('track-list 有轨道但解析无 id'));
    });

    test('空表仍然静默返回（不误报）', () {
      final body = bodyOf(adapter, 'void _parseTracks(Object? value) {');
      expect(body, contains('return;'));
      // 起播早期空表的正常路径不应触发日志。
      expect(body, contains('起播早期轨道表'));
    });
  });
}

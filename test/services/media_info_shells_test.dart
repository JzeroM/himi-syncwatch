import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 695：媒体徽章行 + 「视频详细信息」面板（四壳同构，仅非房间）守卫。
///
/// 【架构】对 `anime4kStatus` 同款「Dart 产数据、壳只渲染」：
/// `mediaInfoSummary.dart` 格式化（标签中文/值英文）→ `mediaInfoJson`
/// 单字段经 NativePlayerState 管道透传 → 四壳解析渲染。
///
/// 【范围】徽章行与面板**仅非房间模式**（产品拍板）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  final summary = read('lib/services/player/media_info_summary.dart');
  final badgeRow = read('lib/widgets/media_badge_row.dart');
  final infoSheet = read('lib/widgets/video_info_sheet.dart');
  final screen = read('lib/screens/player/player_screen.dart');
  final state = read('lib/services/player/native/native_player_state.dart');
  final qtState = read('native/windows_qt_player/src/player_state.h');
  final qtBottom = read('native/windows_qt_player/src/qml/BottomBar.qml');
  final qtPanel = read('native/windows_qt_player/src/qml/MediaInfoPanel.qml');
  final kotlinState =
      read('android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/AndroidNativePlayerState.kt');
  final kotlinView =
      read('android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerScreenView.kt');
  final ohosHost = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiMpvNativeHost.ets');
  final ohosView = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiNativePlayerView.ets');

  group('① Dart 数据管道（mediaInfoJson 单字段）', () {
    test('聚合器格式化产物（徽章/分组）就位', () {
      expect(summary, contains('buildMediaBadges'));
      expect(summary, contains('buildMediaInfoGroups'));
      expect(summary, contains('标签中文'), reason: '占位：文档注释存在');
    });

    test('NativePlayerState 三件套齐（声明/序列化/合并）', () {
      expect(state, contains('final String? mediaInfoJson;'));
      expect(state, contains("'mediaInfoJson': mediaInfoJson"));
      expect(state, contains("json['mediaInfoJson'] as String?"));
    });

    test('player_screen 推送（extras + 非房间门控）', () {
      expect(screen, contains('mediaInfoJson: _mediaInfoJson'));
      expect(screen, contains("if (widget.roomCode != null) return null;"),
          reason: 'mediaInfoJson 仅非房间推送');
      expect(screen, contains('MediaBadgeRow(badges: _mediaBadges)'));
      expect(screen, contains('_openVideoInfoSheet()'));
    });

    test('徽章行/详情面板 widget 就位', () {
      expect(badgeRow, contains('class MediaBadgeRow'));
      expect(badgeRow, contains('MainAxisAlignment.end'),
          reason: '徽章右对齐');
      expect(infoSheet, contains('showVideoInfoSheet'));
      expect(infoSheet, contains('class VideoInfoSheet'));
    });
  });

  group('② Qt 壳（QML）', () {
    test('player_state 暴露 mediaInfoJson', () {
      expect(qtState, contains('Q_PROPERTY(QString mediaInfoJson'));
    });

    test('底栏徽章行 + 信息按钮（仅非房间）', () {
      expect(qtBottom, contains('mediaBadges'));
      expect(qtBottom, contains('signal mediaInfoClicked()'));
      expect(qtBottom, contains('visible: !playerState.isRoom'),
          reason: '徽章/信息按钮仅非房间');
    });

    test('MediaInfoPanel：矩形玻璃分组卡片 + 每条一行', () {
      expect(qtPanel, contains('695：「视频详细信息」面板'), reason: '组件文件');
      expect(qtPanel, contains('mediaGroups'));
      expect(qtPanel, contains('modelData.title'));
      expect(qtPanel, contains('modelData.label'));
    });
  });

  group('③ Android Kotlin 壳', () {
    test('状态解析 mediaInfoJson', () {
      expect(kotlinState, contains('val mediaInfoJson: String? = null'));
      expect(kotlinState, contains('json.optNullableString("mediaInfoJson")'));
    });

    test('徽章行（进度条上方右对齐）+ 信息按钮（底栏最右）', () {
      expect(kotlinView, contains('mediaBadgeRow'));
      expect(kotlinView, contains('Gravity.END'), reason: '徽章右对齐');
      expect(kotlinView, contains('parseMediaBadges(lastState.mediaInfoJson)'));
      expect(kotlinView, contains('NativePlayerIcons.ICON_INFO'));
      expect(kotlinView, contains('showMediaInfoDialog()'));
    });

    test('详情弹窗：分组玻璃卡片 + 每条一行 + 可滚动', () {
      expect(kotlinView, contains('fun showMediaInfoDialog()'));
      expect(kotlinView, contains('android.widget.ScrollView'));
      expect(kotlinView, contains('optJSONArray("groups")'));
    });
  });

  group('④ 鸿蒙 ArkTS 壳', () {
    test('状态解析 mediaInfoJson（host→view→epoch 签名）', () {
      expect(ohosHost, contains('mediaInfoJson: string'));
      expect(ohosHost, contains('jsonStr(obj.mediaInfoJson'));
      expect(ohosView, contains('@State mediaInfoJson: string'));
      expect(ohosView, contains('this.mediaInfoJson = s.mediaInfoJson'));
      expect(ohosView, contains(r'|${this.mediaInfoJson}'),
          reason: '进 epoch 签名（@Builder 刷新依赖）');
    });

    test('徽章行 + 信息按钮 + 详情面板', () {
      expect(ohosView, contains('parseMediaPayload()'));
      expect(ohosView, contains('showMediaInfoDialog()'));
      expect(ohosView, contains('NativePlayerIcons.ICON_INFO'));
      expect(ohosView, contains('MediaInfoDialogContent'));
    });
  });
}

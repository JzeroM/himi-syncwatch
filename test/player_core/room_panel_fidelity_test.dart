import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 592：原生房间资源面板逐项复刻 Flutter `_buildResourcePanel`。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final kotlinIcons = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerIcons.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final flutterPanel = File('lib/screens/player/player_screen.dart')
      .readAsStringSync();

  group('根因：签名初值碰撞（资源面板全空）', () {
    test('安卓签名初值用哨兵，不能是空串', () {
      // 旧初值 `""` 与「零分组」产生的签名 `""` 相等 → buildRoomPanelList
      // 从不执行 → 连「暂无资源」空态都不渲染，列表区纯空白。
      expect(kotlinScreen, contains('ROOM_SIG_UNBUILT'));
      expect(kotlinScreen, contains('private var roomPanelSig: String = ROOM_SIG_UNBUILT'));
      expect(kotlinScreen, contains('private var roomBroadcastSig: String = ROOM_SIG_UNBUILT'));
      expect(kotlinScreen, isNot(contains('private var roomPanelSig: String = ""')));
      expect(kotlinScreen, isNot(contains('private var roomBroadcastSig: String = ""')));
    });
  });

  group('头部：资源 | 搜索 | 人数胶囊 | 角色徽章', () {
    test('搜索显隐：房主且**暂停中**才显示（596 修正 595 的反向条件）', () {
      // Flutter `_roomData != null && _isHost && state != playing`——播放中
      // **不**显示；原生 paused 等价于 state != playing。
      expect(kotlinScreen,
          contains('if (state.isHost && state.paused) VISIBLE else GONE'));
      // 605 起读 @State 镜像。
      expect(ohosView, contains('if (this.roomIsHost && this.paused) {'));
    });

    test('人数胶囊用 people 图标字体（不是 emoji）', () {
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_PEOPLE'));
      expect(kotlinScreen, isNot(contains('"👥 ')));
      expect(ohosView, contains('NativePlayerIcons.ICON_PEOPLE'));
      expect(ohosView, isNot(contains('👥')));
      // 图标字体码点存在。
      expect(kotlinIcons, contains('ICON_PEOPLE = 0xE486'));
    });

    test('人数胶囊底 white12 + 圆角 8 + padding h6 v2', () {
      expect(kotlinScreen, contains('setColor(0x1FFFFFFF)'));
      expect(kotlinScreen, contains('roomOnlineChip.setPadding(dp(6), dp(2), dp(6), dp(2))'));
      expect(ohosView, contains("backgroundColor('#1FFFFFFF')"));
    });

    test('角色徽章：房主 accent / 观众红', () {
      expect(kotlinScreen,
          contains('setColor(if (state.isHost) NPTheme.ACCENT else 0xFFE53935.toInt())'));
      // 605 起读 @State 镜像。
      expect(ohosView, contains("backgroundColor(this.roomIsHost ? SEL_COLOR : '#E53935')"));
    });
  });

  group('分组/季/集三层结构', () {
    test('分组计数 white54 12（旧 WHITE_70 11）', () {
      expect(kotlinScreen, contains('setTextColor(NPTheme.WHITE_54)'));
      expect(kotlinScreen, contains('setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)'));
      expect(ohosView, contains(".fontSize(12)\n                .fontColor('#8AFFFFFF')"));
    });

    test('季标题：玻璃条 + white54 16 图标 + 第N季 + (N集)', () {
      // 680：玻璃化后缩进改为 10/8（对齐 Win 的季标题玻璃条）
      expect(kotlinScreen, contains('setPadding(dp(10), dp(6), dp(8), dp(6))'));
      expect(kotlinScreen, contains('16f,\n                NPTheme.WHITE_54,'));
      expect(kotlinScreen, contains('text = "第\${season.seasonNumber}季"'));
      expect(kotlinScreen, contains('"(\${season.episodes.size}集)"'));
      expect(ohosView, contains('padding({ left: 10, right: 8, top: 6, bottom: 6 })'));
      expect(ohosView, contains('`第\${season.seasonNumber}季`'));
      expect(ohosView, contains('`(\${season.episodes.length}集)`'));
    });

    test('季标题只在剧集组显示（电影组直接列集）', () {
      // 安卓：group.isMovie 分支直接列 seasons.first.episodes 后 return。
      expect(kotlinScreen, contains('if (group.isMovie) {'));
      expect(kotlinScreen, contains('group.seasons.firstOrNull()?.episodes?.forEach'));
      expect(ohosView, contains('if (g.isMovie) {'));
      expect(ohosView, contains('g.seasons.length > 0 ? g.seasons[0].episodes : []'));
    });
  });

  group('集行：左边框 + 播放图标 + 缩略图 + 集码 + 删除', () {
    test('当前集左 3dp accent 边框（不占布局宽，596）', () {
      // 旧实现用独立 View 占 3dp 宽 → 视觉多一条竖条 + 右推内容。
      // Flutter 是 Border(left, 3) 内边缘描边。
      expect(kotlinScreen, contains('foreground = leftAccentDivider()'));
      expect(kotlinScreen, contains('private fun leftAccentDivider()'));
      expect(ohosView, contains('width: { left: 3 }, color: SEL_COLOR'));
    });

    test('当前集底色 accent@30%（680：改为玻璃卡 + 主色描边）', () {
      // 680：整行玻璃卡（10 圆角），选中态 accent 底 + 2dp 主色描边
      expect(kotlinScreen, contains('0x386366F1'));
      expect(kotlinScreen, contains('setStroke(dp(if (ep.isPlaying) 2 else 1)'));
      expect(ohosView, contains("'#386366F1'"));
      expect(ohosView, contains('borderRadius(10)'));
    });

    test('缩略图圆角 4 + 无图时灰底 + movie 图标', () {
      expect(kotlinScreen, contains('cornerRadius = dp(4).toFloat()'));
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_MOVIE'));
      expect(ohosView, contains('NativePlayerIcons.ICON_MOVIE'));
      expect(ohosView, contains("backgroundColor('#424242')"));
    });

    test('播放/暂停图标随状态切换', () {
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_PAUSE_CIRCLE'));
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_PLAY_CIRCLE'));
      expect(ohosView, contains('NativePlayerIcons.ICON_PAUSE_CIRCLE'));
      expect(ohosView, contains('NativePlayerIcons.ICON_PLAY_CIRCLE'));
    });

    test('删除按钮 close 18 white24', () {
      expect(kotlinScreen, contains('iconView(NativePlayerIcons.ICON_CLOSE, 18f, NPTheme.WHITE_24)'));
      expect(ohosView, contains('NativePlayerIcons.ICON_CLOSE'));
    });
  });

  group('播报板', () {
    test('标题含 campaign 图标（旧实现只有文本）', () {
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_CAMPAIGN'));
      expect(ohosView, contains('NativePlayerIcons.ICON_CAMPAIGN'));
    });

    test('新消息自动滚到底', () {
      expect(kotlinScreen, contains('roomBroadcastScroll.fullScroll(View.FOCUS_DOWN)'));
    });

    test('空态居中', () {
      expect(kotlinScreen, contains('text = "暂无消息"'));
      expect(kotlinScreen, contains('gravity = Gravity.CENTER'));
      expect(ohosView, contains("Text('暂无消息')"));
    });
  });

  group('列表内边距与 Flutter 对齐', () {
    test('分组列表 padding vertical 4', () {
      expect(kotlinScreen, contains('roomPanelList.setPadding(0, dp(4), 0, dp(4))'));
      expect(ohosView, contains('.padding({ top: 4, bottom: 4 })'));
    });
  });

  group('Flutter 参考实现（对齐基准）', () {
    test('头部搜索条件', () {
      expect(flutterPanel, contains('_roomData != null &&'));
      expect(flutterPanel, contains('_isHost &&'));
      expect(flutterPanel, contains('_player.state != AdapterPlaybackState.playing'));
    });

    test('679：集行改为玻璃卡 + 主色 2px 描边（原左边框 3 + accent@0.3 底）', () {
      // 用户要求「行要玻璃卡片感」：左边框竖条改为整行玻璃卡 + 选中描边。
      expect(flutterPanel, contains('Border.all('));
      expect(flutterPanel, contains('width: 2,'));
      expect(flutterPanel, contains('GlassContainer'));
    });

    test('679：季标题改为玻璃条（原 left 24 缩进改 8+内距）', () {
      expect(flutterPanel,
          contains('EdgeInsets.only(left: 8, right: 4, top: 2)'));
    });
  });
}

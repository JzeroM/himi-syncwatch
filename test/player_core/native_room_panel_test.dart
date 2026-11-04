import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_command.dart';
import 'package:himi_syncwatch/services/player/native/native_player_state.dart';

/// 590 批次：弹幕行分配重建、角标空值/裁剪、四端二维码、原生房间资源面板。
void main() {
  final kotlinDanmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();
  final ohosDanmaku = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DanmakuLayer.ets',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final qrService =
      File('lib/services/qr_export_service.dart').readAsStringSync();
  final playerScreen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final roomScreen =
      File('lib/screens/room/room_screen.dart').readAsStringSync();

  group('弹幕行分配：冲突表按在场集合重建（禁跨帧累积）', () {
    test('安卓：分配前 fill(0) 重建三组冲突表', () {
      // 根因：旧实现把 avail[] 当跨帧持久状态，离场条目的占用不释放 →
      // 新条目找不到空行 → 只显示最顶一行、一条条冒出来。
      expect(kotlinDanmaku, contains('scrollAvail.fill(0.0)'));
      expect(kotlinDanmaku, contains('topAvail.fill(0.0)'));
      expect(kotlinDanmaku, contains('bottomAvail.fill(0.0)'));
      expect(kotlinDanmaku, contains('① 重建冲突表'));
      // 重建时必须按 laneOf 回填已分配条目的占用。
      expect(kotlinDanmaku, contains('val lane = laneOf[keyOf(item)] ?: continue'));
      expect(kotlinDanmaku, contains('if (occupiedUntil > avail[lane]) avail[lane] = occupiedUntil'));
      // 行号仍绑定生命周期（不跳行）。
      expect(kotlinDanmaku, contains('if (laneOf.containsKey(key)) continue'));
    });

    test('鸿蒙：同款重建（两端逻辑同构，同样有此 bug）', () {
      expect(ohosDanmaku, contains('this.scrollRowAvail.fill(0)'));
      expect(ohosDanmaku, contains('this.topRowAvail.fill(0)'));
      expect(ohosDanmaku, contains('this.bottomRowAvail.fill(0)'));
      expect(ohosDanmaku, contains('① 重建冲突表'));
      expect(ohosDanmaku, contains('if (this.laneOf.has(key))'));
    });

    test('两端都有 occupancyMs 抽取（重建与分配共用同一占用公式）', () {
      expect(kotlinDanmaku, contains('private fun occupancyMs('));
      expect(ohosDanmaku, contains('private occupancyMs('));
    });
  });

  group('角标：空/0 不显示（禁空白圆点）', () {
    test('安卓创建时即 GONE（吸收短路歧义）', () {
      // badgeLastText 是 HashMap<TextView, String?>，缺键取 null 与值为 null
      // 无法区分 → 首次 provider 返回 null 时短路，visibility 从未设 GONE。
      expect(kotlinScreen, contains('visibility = GONE'));
      expect(kotlinScreen, contains('创建时即 GONE'));
    });

    test('badgeText 统一入口（count > 0 才返回字符串）', () {
      expect(kotlinScreen, contains('internal fun badgeText(count: Int): String?'));
      expect(kotlinScreen, contains('if (count > 0) count.toString() else null'));
      // 四处 provider 全部改用它。
      expect(kotlinScreen, contains('{ badgeText(lastState.versions.size) }'));
      expect(kotlinScreen, contains('{ badgeText(lastState.subtitleStreamCount) }'));
      expect(kotlinScreen, contains('{ badgeText(lastState.audioStreamCount) }'));
      expect(kotlinScreen, contains('{ badgeText(lastState.episodes.size) }'));
    });

    test('applyState 二次兜底挡住 "0"/空白串', () {
      expect(kotlinScreen, contains('toIntOrNull()?.takeIf { it > 0 }?.toString()'));
    });
  });

  group('角标：收进 32dp 命中框（禁依赖父级裁剪）', () {
    test('marginEnd 归零（旧 -2dp 会伸出 host 被裁）', () {
      expect(kotlinScreen, contains('marginEnd = 0'));
      // 注释里保留旧写法说明（「旧实现 marginEnd = -dp(2)」），所以只断言
      // 函数体内（签名之后到下一个 `marginEnd` 赋值）没有 -dp(2)。
      final start = kotlinScreen.indexOf(
        'private fun badgeLayoutParams(text: String): LayoutParams {',
      );
      expect(start, greaterThan(0));
      final body = kotlinScreen.substring(start, start + 260);
      expect(body, isNot(contains('marginEnd = -dp(2)')));
    });

    test('仍保持正方形（OVAL 必为正圆）', () {
      expect(kotlinScreen, matches(RegExp(r'LayoutParams\(sidePx, sidePx')));
    });
  });

  group('二维码保存：四端统一（禁直写 DCIM）', () {
    test('统一服务按平台分派', () {
      expect(qrService, contains('class QrExportService'));
      expect(qrService, contains("MethodChannel('himi/gallery_saver')"));
      expect(qrService, contains('MediaStore'));
      expect(qrService, contains('photoAccessHelper'));
      expect(qrService, contains('PHPhotoLibrary'));
    });

    test('两处调用点都不再直写 DCIM、不再拦鸿蒙', () {
      // 注释里保留旧实现说明（「旧实现直写 .../DCIM/Himi」），因此断言
      // **可执行代码**不出现：`Directory('/storage/emulated/0/DCIM...`。
      for (final src in <String>[playerScreen, roomScreen]) {
        expect(src, isNot(contains("Directory('/storage/emulated/0/DCIM")));
        expect(src, isNot(contains('鸿蒙暂不支持系统分享')));
        expect(src, contains('QrExportService'));
      }
    });

    test('安卓 MediaStore 两阶段写入 + 权限仅限 API 28', () {
      final saver = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/GallerySaverPlugin.kt',
      ).readAsStringSync();
      expect(saver, contains('MediaStore.Images.Media.EXTERNAL_CONTENT_URI'));
      expect(saver, contains('MediaStore.Images.Media.RELATIVE_PATH'));
      expect(saver, contains('MediaStore.Images.Media.IS_PENDING'));
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
      expect(manifest, contains('android:maxSdkVersion="28"'));
    });

    test('对话框自持二维码 key（禁跨层传 key 的时序陷阱）', () {
      final dialog =
          File('lib/widgets/room/room_share_dialog.dart').readAsStringSync();
      expect(dialog, contains('final GlobalKey _qrKey = GlobalKey();'));
      expect(dialog, contains('Future<Uint8List?> _captureBytes()'));
      expect(dialog, isNot(contains('required this.qrKey')));
      expect(dialog, contains('onShareQr(await _captureBytes())'));
      expect(dialog, contains('onSaveQr(await _captureBytes())'));
    });
  });

  group('房间资源面板数据模型', () {
    test('NativeResourceItem roundtrip + 集码', () {
      const item = NativeResourceItem(
        index: 3,
        name: '沈家灭门',
        season: 1,
        number: 3,
        poster: 'https://x/p.jpg',
        isPlaying: true,
      );
      final back = NativeResourceItem.fromJson(item.toJson());
      expect(back.index, 3);
      expect(back.name, '沈家灭门');
      expect(back.season, 1);
      expect(back.number, 3);
      expect(back.isPlaying, isTrue);
      expect(back.episodeCode, 'S01E03');
      expect(back.isMovie, isFalse);
    });

    test('电影 isMovie + 空集码', () {
      const movie = NativeResourceItem(index: 0, name: '电影名');
      expect(movie.isMovie, isTrue);
      expect(movie.episodeCode, '');
    });

    test('分组/季 roundtrip + 计数标签', () {
      const group = NativeResourceGroup(
        name: '嫁金钗',
        isMovie: false,
        collapsed: false,
        seasons: <NativeSeasonGroup>[
          NativeSeasonGroup(
            seasonNumber: 1,
            collapsed: false,
            episodes: <NativeResourceItem>[
              NativeResourceItem(index: 0, name: '第1集', season: 1, number: 1),
              NativeResourceItem(index: 1, name: '第2集', season: 1, number: 2),
            ],
          ),
        ],
      );
      expect(group.totalCount, 2);
      expect(group.countLabel, '(2集)');
      final back = NativeResourceGroup.fromJson(group.toJson());
      expect(back.name, '嫁金钗');
      expect(back.isMovie, isFalse);
      expect(back.seasons.single.seasonNumber, 1);
      expect(back.seasons.single.episodes.length, 2);
      expect(back.seasons.single.episodes.first.episodeCode, 'S01E01');

      const movieGroup = NativeResourceGroup(
        name: '电影',
        isMovie: true,
        seasons: <NativeSeasonGroup>[
          NativeSeasonGroup(
            seasonNumber: 0,
            episodes: <NativeResourceItem>[
              NativeResourceItem(index: 0, name: '电影名'),
            ],
          ),
        ],
      );
      expect(movieGroup.countLabel, '(1)');
    });

    test('Kotlin 字符串模板紧跟中文必须用花括号包裹（防 Unresolved reference）', () {
      // CI 真机编译失败：Kotlin 把 `"$totalCount集"` 里的 `totalCount集`
      // 整体当成标识符（中文字符是合法标识符字符）→ Unresolved reference。
      final state = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'AndroidNativePlayerState.kt',
      ).readAsStringSync();
      expect(state, contains(r'(${totalCount}集)'));
      expect(state, isNot(contains(r'($totalCount集)')));
      // 全仓扫描：任何 `$ident` 后紧跟中文的简单模板都视为隐患。
      final badPattern = RegExp(r'\$[a-zA-Z_][a-zA-Z0-9_]*(?=[\u4e00-\u9fff])');
      for (final f in Directory(
        'android/app/src/main/kotlin/com/himi/syncwatch',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.kt')) continue;
        // 逐行扫描并跳过注释行（注释里会写「旧写法 `$var中文`」做说明，
        // 那不是可执行代码）。
        final hits = <String>[];
        for (final line in f.readAsStringSync().split('\n')) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*') ||
              trimmed.startsWith('/*')) {
            continue;
          }
          for (final m in badPattern.allMatches(line)) {
            // 排除 `${...}`（有花括号的合法形式）。
            if (line.substring(m.end).startsWith('}')) continue;
            hits.add('${f.path}: $line');
          }
        }
        expect(hits, isEmpty,
            reason: '${f.path} 存在美元变量紧跟中文的简单模板');
      }
    });

    test('extras 携带房间字段', () {
      const extras = NativePlayerUiExtras(
        roomCode: 'ABC123',
        isHost: true,
        onlineUserCount: 5,
        audienceName: '小明',
        broadcasts: <String>['[09:07] 房主 加入了房间'],
        resourcePanelOpen: true,
      );
      expect(extras.roomCode, 'ABC123');
      expect(extras.isHost, isTrue);
      expect(extras.onlineUserCount, 5);
      expect(extras.audienceName, '小明');
      expect(extras.broadcasts.single, '[09:07] 房主 加入了房间');
      expect(extras.resourcePanelOpen, isTrue);
      // 默认值。
      const defaults = NativePlayerUiExtras();
      expect(defaults.roomCode, isNull);
      expect(defaults.isHost, isFalse);
      expect(defaults.resourceGroups, isEmpty);
      expect(defaults.resourcePanelOpen, isTrue);
    });
  });

  group('房间资源面板命令路由', () {
    test('四个新命令可往返解析', () {
      final group = NativePlayerCommand.fromMap(
        <Object?, Object?>{'type': 'toggleResourceGroup', 'index': 2},
      );
      expect(group, isA<ToggleResourceGroup>());
      expect((group as ToggleResourceGroup).index, 2);

      final season = NativePlayerCommand.fromMap(<Object?, Object?>{
        'type': 'toggleResourceSeason',
        'groupIndex': 1,
        'seasonIndex': 0,
      });
      expect(season, isA<ToggleResourceSeason>());
      expect((season as ToggleResourceSeason).groupIndex, 1);

      final remove = NativePlayerCommand.fromMap(
        <Object?, Object?>{'type': 'removeResourceEpisode', 'index': 4},
      );
      expect(remove, isA<RemoveResourceEpisode>());
      expect((remove as RemoveResourceEpisode).index, 4);

      final search = NativePlayerCommand.fromMap(
        <Object?, Object?>{'type': 'openResourceSearch'},
      );
      expect(search, isA<OpenResourceSearch>());
    });

    test('toMap 往返一致', () {
      expect(
        const ToggleResourceGroup(index: 3).toMap(),
        <String, Object?>{'type': 'toggleResourceGroup', 'index': 3},
      );
      expect(
        const ToggleResourceSeason(groupIndex: 1, seasonIndex: 2).toMap(),
        <String, Object?>{
          'type': 'toggleResourceSeason',
          'groupIndex': 1,
          'seasonIndex': 2,
        },
      );
      expect(
        const RemoveResourceEpisode(index: 5).toMap(),
        <String, Object?>{'type': 'removeResourceEpisode', 'index': 5},
      );
      expect(
        const OpenResourceSearch().toMap(),
        <String, Object?>{'type': 'openResourceSearch'},
      );
    });
  });

  group('原生资源面板：实现与 surface 收窄', () {
    test('安卓面板结构与交互齐全', () {
      expect(kotlinScreen, contains('private fun configureRoomPanel()'));
      expect(kotlinScreen, contains('private fun renderRoomPanel()'));
      expect(kotlinScreen, contains('private fun buildRoomPanelList('));
      expect(kotlinScreen, contains('onToggleResourceGroup(gi)'));
      expect(kotlinScreen, contains('onToggleResourceSeason(gi, si)'));
      expect(kotlinScreen, contains('onRemoveResourceEpisode(ep.index)'));
      expect(kotlinScreen, contains('onOpenResourceSearch()'));
      // 视觉对齐 Flutter：0xFF1A1A2E 底 + 组标题 0xFF16213E。
      expect(kotlinScreen, contains('0xFF1A1A2E'));
      expect(kotlinScreen, contains('0xFF16213E'));
    });

    test('面板展开时通知宿主收窄 surface（否则视频被遮）', () {
      expect(kotlinScreen, contains('listener?.onVideoInsetRight(panelPx)'));
      expect(kotlinScreen, contains('ROOM_PANEL_WIDTH'));
      final host = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'AndroidNativePlayerHost.kt',
      ).readAsStringSync();
      expect(host, contains('private fun applyVideoInsetRight('));
      expect(host, contains('override fun onVideoInsetRight(insetPx: Int)'));
    });

    test('PlayerScreen 注入房间数据 + 命令真正生效', () {
      expect(playerScreen, contains('roomCode: widget.roomCode'));
      expect(playerScreen, contains('resourceGroups: _nativeResourceGroups()'));
      expect(playerScreen, contains('resourcePanelOpen: _showPanel'));
      expect(playerScreen, contains('List<NativeResourceGroup> _nativeResourceGroups()'));
      // ToggleResourcePanel 不再只打日志。
      expect(playerScreen, contains('setState(() => _showPanel = !_showPanel);'));
      expect(playerScreen,
          isNot(contains("'原生 UI 请求切换资源面板（Phase 5 待接入）'")));
    });
  });
}

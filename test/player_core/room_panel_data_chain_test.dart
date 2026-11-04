import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_state.dart';

/// 595：房间资源面板数据链路（构造 → toJson → fromJson）+ 分栏几何。
///
/// 【真机「资源面板永远空白、开关点了没反应」根因】`onlineUserCount` /
/// `audienceName` / `resourceGroups` / `broadcasts` / `resourcePanelOpen`
/// 此前只存在于 `NativePlayerUiExtras`，**从未进入 `NativePlayerState`**
/// ——构造时漏传、toJson 未序列化、fromJson 未解析。原生
/// `optJSONArray("resourceGroups")` 永远 null、
/// `optBoolean("resourcePanelOpen", true)` 永远默认 true。
void main() {
  group('NativePlayerState 携带房间资源面板字段', () {
    const group = NativeResourceGroup(
      name: '兰香如故',
      isMovie: false,
      collapsed: false,
      seasons: <NativeSeasonGroup>[
        NativeSeasonGroup(
          seasonNumber: 1,
          collapsed: false,
          episodes: <NativeResourceItem>[
            NativeResourceItem(index: 0, name: '第1集', season: 1, number: 1),
          ],
        ),
      ],
    );

    test('构造 + 字段可读', () {
      const state = NativePlayerState(
        roomCode: 'ABC123',
        isHost: false,
        onlineUserCount: 3,
        audienceName: '小明',
        resourceGroups: <NativeResourceGroup>[group],
        broadcasts: <String>['[09:07] 房主 加入了房间'],
        resourcePanelOpen: false,
      );
      expect(state.onlineUserCount, 3);
      expect(state.audienceName, '小明');
      expect(state.resourceGroups.single.name, '兰香如故');
      expect(state.broadcasts.single, '[09:07] 房主 加入了房间');
      expect(state.resourcePanelOpen, isFalse);
    });

    test('默认值', () {
      const state = NativePlayerState();
      expect(state.onlineUserCount, 0);
      expect(state.audienceName, isNull);
      expect(state.resourceGroups, isEmpty);
      expect(state.broadcasts, isEmpty);
      expect(state.resourcePanelOpen, isTrue);
    });

    test('toJson → fromJson 往返保留全部字段', () {
      const state = NativePlayerState(
        roomCode: 'ABC123',
        isHost: true,
        onlineUserCount: 5,
        audienceName: '房主',
        resourceGroups: <NativeResourceGroup>[group],
        broadcasts: <String>['消息1', '消息2'],
        resourcePanelOpen: false,
      );
      final back = NativePlayerState.fromJson(state.toJson());
      expect(back.onlineUserCount, 5);
      expect(back.audienceName, '房主');
      expect(back.resourceGroups.single.name, '兰香如故');
      expect(
        back.resourceGroups.single.seasons.single.episodes.single.episodeCode,
        'S01E01',
      );
      expect(back.broadcasts, <String>['消息1', '消息2']);
      expect(back.resourcePanelOpen, isFalse);
    });

    test('toJson 含全部 5 个键（防漏序列化回归）', () {
      final json = const NativePlayerState().toJson();
      for (final key in <String>[
        'onlineUserCount',
        'audienceName',
        'resourceGroups',
        'broadcasts',
        'resourcePanelOpen',
      ]) {
        expect(json.containsKey(key), isTrue, reason: 'toJson 缺 $key');
      }
    });

    test('copyWith 可单独覆盖（开关面板）', () {
      const state = NativePlayerState(resourcePanelOpen: true);
      final hidden = state.copyWith(resourcePanelOpen: false);
      expect(hidden.resourcePanelOpen, isFalse);
      // 其它字段保持不变。
      expect(hidden.onlineUserCount, state.onlineUserCount);
      // 反向。
      expect(hidden.copyWith(resourcePanelOpen: true).resourcePanelOpen, isTrue);
    });

    test('相等性包含新字段（防 switch 面板后判等为同一状态）', () {
      const a = NativePlayerState(resourcePanelOpen: true);
      const b = NativePlayerState(resourcePanelOpen: false);
      expect(a == b, isFalse, reason: 'resourcePanelOpen 不同必须判不等');
      expect(a.hashCode == b.hashCode, isFalse);

      const c = NativePlayerState(onlineUserCount: 1);
      const d = NativePlayerState(onlineUserCount: 2);
      expect(c == d, isFalse);
    });
  });

  group('NativePlayerUiExtras 侧（数据源）', () {
    test('extras 携带同样字段', () {
      const extras = NativePlayerUiExtras(
        roomCode: 'ABC123',
        isHost: true,
        onlineUserCount: 4,
        audienceName: '小明',
        broadcasts: <String>['x'],
        resourcePanelOpen: false,
      );
      expect(extras.onlineUserCount, 4);
      expect(extras.audienceName, '小明');
      expect(extras.broadcasts.single, 'x');
      expect(extras.resourcePanelOpen, isFalse);
    });
  });
}

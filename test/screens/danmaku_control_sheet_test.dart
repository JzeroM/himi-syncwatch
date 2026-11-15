import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/danmaku_control_sheet.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_search_controller.dart';

class _FakeClient extends DandanplayClient {
  _FakeClient({this.result = const []}) : super(baseUrl: 'http://fake.local');

  final List<MatchCandidate> result;

  @override
  Future<List<MatchCandidate>> searchEpisodes(
    String keyword, {
    int? episode,
  }) async =>
      result;
}

/// 内存记忆仓库（widget 测试禁止真实文件 IO——FakeAsync 会死锁）。
class _FakeMemory implements DanmakuMatchRepository {
  final Map<String, DanmakuMatchRecord> map = {};

  @override
  Future<DanmakuMatchRecord?> get({String? itemKey, String? nameKey}) async =>
      map[itemKey] ?? map[nameKey];

  @override
  Future<void> put({
    String? itemKey,
    String? nameKey,
    required DanmakuMatchRecord record,
  }) async {
    if (itemKey != null) map[itemKey] = record;
    if (nameKey != null) map[nameKey] = record;
  }

  @override
  Future<void> remove({String? itemKey, String? nameKey}) async {
    map.remove(itemKey);
    map.remove(nameKey);
  }

  @override
  Future<List<DanmakuMatchEntry>> all() async => [
        for (final e in map.entries)
          DanmakuMatchEntry(key: e.key, record: e.value),
      ];

  @override
  Future<void> clear() async => map.clear();
}

void main() {
  late _FakeMemory memory;

  setUp(() {
    memory = _FakeMemory();
  });

  Future<DanmakuSearchController> makeController({
    DandanplayClient? client,
  }) async {
    final c = DanmakuSearchController(
      client: client ??
          _FakeClient(result: const [
            MatchCandidate(
              episodeId: 101,
              animeTitle: '葬送的芙莉莲',
              episodeTitle: '第1集',
            ),
            MatchCandidate(
              episodeId: 102,
              animeTitle: '葬送的芙莉莲',
              episodeTitle: '第2集',
            ),
          ]),
      itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'),
      nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'),
      memory: memory,
    );
    await c.load();
    return c;
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required DanmakuSearchController controller,
    bool danmakuOn = true,
    VoidCallback? onToggle,
    VoidCallback? onReload,
    String prefill = '葬送的芙莉莲',
    int episodeNumber = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DanmakuControlSheet(
          controller: controller,
          danmakuOn: danmakuOn,
          onToggle: onToggle ?? () {},
          onReload: onReload ?? () {},
          prefillKeyword: prefill,
          currentEpisodeNumber: episodeNumber,
        ),
      ),
    ));
  }

  group('弹窗主体（开关 + 状态行）', () {
    testWidgets('渲染动效开关与绑定状态行', (tester) async {
      final controller = await makeController();
      await pumpSheet(tester, controller: controller);
      expect(find.text('弹幕'), findsOneWidget);
      expect(find.byKey(const Key('danmaku-switch')), findsOneWidget);
      expect(find.textContaining('已开启'), findsOneWidget);
      expect(find.text('未匹配'), findsOneWidget);
    });

    testWidgets('点击开关触发 onToggle（开关能力全在弹窗内）', (tester) async {
      final controller = await makeController();
      var toggled = 0;
      await pumpSheet(tester,
          controller: controller, danmakuOn: true, onToggle: () => toggled++);
      await tester.tap(find.byKey(const Key('danmaku-switch')));
      await tester.pump();
      expect(toggled, 1);
      expect(find.textContaining('已关闭'), findsOneWidget);
    });
  });

  group('搜索 / 换绑', () {
    testWidgets('预填关键词进入搜索态并渲染结果', (tester) async {
      final controller = await makeController();
      await pumpSheet(tester, controller: controller);
      await tester.tap(find.text('搜索 / 换绑'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '葬送的芙莉莲');

      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('葬送的芙莉莲'), findsWidgets);
      expect(find.text('第1集'), findsOneWidget);
    });

    testWidgets('「只看第 N 集」过滤生效', (tester) async {
      final controller = await makeController();
      await pumpSheet(tester,
          controller: controller, prefill: 'x', episodeNumber: 2);
      await tester.tap(find.text('搜索 / 换绑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      // 默认勾选「只看第 2 集」→ 只剩第2集
      expect(find.text('第1集'), findsNothing);
      expect(find.text('第2集'), findsOneWidget);

      await tester.tap(find.text('只看第 2 集'));
      await tester.pumpAndSettle();
      expect(find.text('第1集'), findsOneWidget);
    });

    testWidgets('绑定写 manual 记忆并触发 onReload', (tester) async {
      final controller = await makeController();
      var reloaded = 0;
      await pumpSheet(tester,
          controller: controller, onReload: () => reloaded++);
      await tester.tap(find.text('搜索 / 换绑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('绑定').first);
      await tester.pumpAndSettle();
      expect(reloaded, 1);
      expect(controller.binding?.source, DanmakuMatchSource.manual);
      // 绑定后回到主态，状态行/列表均显示手动绑定
      expect(find.textContaining('手动'), findsWidgets);
    });

    testWidgets('解除绑定清记忆并重载', (tester) async {
      final controller = await makeController();
      await controller.bind(const MatchCandidate(
        episodeId: 101,
        animeTitle: '葬送的芙莉莲',
        episodeTitle: '第1集',
      ));
      var reloaded = 0;
      await pumpSheet(tester,
          controller: controller, onReload: () => reloaded++);
      await tester.tap(find.text('解除绑定'));
      await tester.pumpAndSettle();
      expect(reloaded, 1);
      expect(controller.binding, isNull);
      expect(
        await memory.get(
            itemKey: DanmakuMatchKeys.item('http://s1', 'item-1')),
        isNull,
      );
    });
  });

  group('player_screen 接线（源码断言）', () {
    String read(String path) => File(path).readAsStringSync();

    test('弹幕按钮点击走弹窗，不再直接 toggle', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(screen, contains('onTap: _openDanmakuPanel,'));
      expect(screen, contains('void _openDanmakuPanel()'));
      expect(
        screen,
        isNot(contains(
            'icon: _danmakuOn ? Icons.comment : Icons.comments_disabled,\n'
            '                    focusNode: _danmakuButtonFocusNode,\n'
            '                    onTap: _toggleDanmaku,')),
      );
    });

    test('按钮图标随开关状态变色', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(
        screen,
        contains("iconColor: _danmakuOn ? const Color(0xFFFF8A3D) : null,"),
      );
    });

    test('失败提示指向弹窗入口', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(screen, contains('未匹配到弹幕，点击弹幕按钮手动搜索'));
    });

    test('弹窗内绑定/解绑后触发弹幕重载', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(
        screen,
        contains('onReload: () => unawaited(_loadDanmaku(force: true)),'),
      );
    });
  });
}

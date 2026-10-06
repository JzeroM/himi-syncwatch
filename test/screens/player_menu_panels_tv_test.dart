import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/decode_mode_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/speed_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/audio_track_menu_panel.dart';

import '../helpers/test_fakes.dart';

/// 仅实现菜单面板用到的成员，其余经 noSuchMethod 转发
///（fvp `Player` 需加载 libmdk.so，测试环境无法真实构造）。
class _FakePlayer implements mdk.Player {
  final List<int> audioTracks;

  _FakePlayer({this.audioTracks = const []});

  @override
  List<int> get activeAudioTracks => audioTracks;

  @override
  List<int> get activeSubtitleTracks => const [];

  @override
  set activeSubtitleTracks(List<int> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child, {AppSettings settings = const AppSettings()}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

int _focusCount(WidgetTester tester) => find
    .byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable')
    .evaluate()
    .length;

MediaStream _stream(String type, int index, {String? label}) => MediaStream(
      type: type,
      codec: type == 'Subtitle' ? 'subrip' : 'aac',
      index: index,
      displayTitle: label,
    );

void main() {
  // ---- 解码方式菜单（播放器顶栏） ----

  testWidgets('TV：解码菜单三个选项均可聚焦，OK 选择软解', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(
      DecodeModePanel(onSwitchMode: (m) => picked = m),
      settings: const AppSettings(tvMode: true, decodeMode: 'auto'),
    ));
    await tester.pump();

    expect(find.text('解码模式'), findsOneWidget, reason: '顶栏图标化后标题移入面板');
    expect(find.text('智能'), findsNWidgets(2), reason: '标题回显 + 选项行各一处');
    expect(find.text('硬解'), findsOneWidget);
    expect(find.text('软解'), findsOneWidget);
    expect(_focusCount(tester), 3, reason: '三选项均应有 D-pad 焦点');

    // 首选项自动聚焦，Enter 直接选择
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvFocusable',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, 'auto', reason: '默认聚焦首个选项（智能）');
  });

  testWidgets('TV：解码菜单方向键移动焦点后 Enter 选择', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(
      DecodeModePanel(onSwitchMode: (m) => picked = m),
      settings: const AppSettings(tvMode: true, decodeMode: 'auto'),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // 落焦首个
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(picked, 'hw', reason: '↓ 移到硬解后 OK 应选中硬解');
  });

  testWidgets('非 TV：解码菜单无焦点节点，点击照常选择', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(
      DecodeModePanel(onSwitchMode: (m) => picked = m),
    ));
    await tester.pump();

    expect(_focusCount(tester), 0);
    await tester.tap(find.text('软解'));
    await tester.pump();
    expect(picked, 'sw');
  });

  // ---- 字幕菜单 ----

  testWidgets('TV：字幕菜单选项可聚焦，点选项回调并关菜单', (tester) async {
    int? selected;
    var closed = false;
    await tester.pumpWidget(_host(
      SubtitleMenuPanel(
        player: _FakePlayer(),
        subtitleStreams: [
          _stream('Subtitle', 0, label: '中字'),
          _stream('Subtitle', 1, label: '英字'),
        ],
        activeSubtitleIndex: 0,
        onSubtitleSelected: (i) => selected = i,
        onLoadLocal: () {},
        onClose: () => closed = true,
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    // 关闭字幕 + 两个字幕轨 + 加载本地字幕 = 4 个可聚焦项
    expect(_focusCount(tester), 4);
    expect(find.text('关闭字幕'), findsOneWidget);

    await tester.tap(find.text('英字'));
    await tester.pump();
    expect(selected, 1);
    expect(closed, isTrue);
  });

  testWidgets('非 TV：字幕菜单无焦点节点，点击照常', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(
      SubtitleMenuPanel(
        player: _FakePlayer(),
        subtitleStreams: [_stream('Subtitle', 0, label: '中字')],
        activeSubtitleIndex: null,
        onSubtitleSelected: (i) => selected = i,
        onLoadLocal: () {},
        onClose: () {},
      ),
    ));
    await tester.pump();

    expect(_focusCount(tester), 0);
    await tester.tap(find.text('中字'));
    await tester.pump();
    expect(selected, 0);
  });

  // ---- 音轨菜单 ----

  testWidgets('TV：音轨菜单选项可聚焦，点选项回调并关菜单', (tester) async {
    int? selected;
    var closed = false;
    await tester.pumpWidget(_host(
      AudioTrackMenuPanel(
        player: _FakePlayer(audioTracks: const [0]),
        audioStreams: [
          _stream('Audio', 0, label: '国语'),
          _stream('Audio', 1, label: '英语'),
        ],
        currentAudioIndex: 0,
        onAudioSelected: (i) => selected = i,
        onClose: () => closed = true,
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    expect(_focusCount(tester), 2);
    await tester.tap(find.text('英语'));
    await tester.pump();
    expect(selected, 1);
    expect(closed, isTrue);
  });

  testWidgets('非 TV：音轨菜单无焦点节点，点击照常', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(
      AudioTrackMenuPanel(
        player: _FakePlayer(),
        audioStreams: [_stream('Audio', 0, label: '国语')],
        onAudioSelected: (i) => selected = i,
        onClose: () {},
      ),
    ));
    await tester.pump();

    expect(_focusCount(tester), 0);
    await tester.tap(find.text('国语'));
    await tester.pump();
    expect(selected, 0);
  });

  // ---- 选择器面板 TV 落焦（打开后焦点直接进面板选中行） ----
  // 根因：焦点停在控制条按钮上时，行内 autofocus 不抢占，D-pad 方向
  // 键落到邻近按钮而非面板；播放页改为打开后显式 requestFocus。

  bool _rowHoldsNode(WidgetTester tester, FocusNode node, String label) => find
      .ancestor(
        of: find.text(label),
        matching:
            find.byWidgetPredicate((w) => w is Focus && w.focusNode == node),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('TV：倍速面板落焦当前档位行，↓ + OK 直接换档', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    double? picked;
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '倍速',
        child: SpeedMenuPanel(
          current: 1.5,
          focusNode: node,
          onSelected: (s) => picked = s,
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    expect(_rowHoldsNode(tester, node, '1.5x'), isTrue, reason: '焦点节点应挂在当前档位行');
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue, reason: 'requestFocus 后面板行持焦');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, 2.0, reason: '落焦行 ↓ 即达 2.0x，OK 直接选中');
  });

  testWidgets('TV：倍速当前档不在档位表（1.75x）回退落焦第一档', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '倍速',
        child: SpeedMenuPanel(
          current: 1.75,
          focusNode: node,
          onSelected: (_) {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();
    expect(_rowHoldsNode(tester, node, '0.5x'), isTrue);
  });

  testWidgets('TV：字幕面板无选中落焦「关闭字幕」行', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '字幕',
        child: SubtitleMenuPanel(
          player: _FakePlayer(),
          subtitleStreams: [_stream('Subtitle', 0, label: '中字')],
          activeSubtitleIndex: null,
          focusNode: node,
          onSubtitleSelected: (_) {},
          onLoadLocal: () {},
          onClose: () {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();
    expect(_rowHoldsNode(tester, node, '关闭字幕'), isTrue);
  });

  testWidgets('TV：字幕面板有选中落焦对应字幕轨行', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '字幕',
        child: SubtitleMenuPanel(
          player: _FakePlayer(),
          subtitleStreams: [
            _stream('Subtitle', 0, label: '中字'),
            _stream('Subtitle', 1, label: '英字'),
          ],
          activeSubtitleIndex: 1,
          focusNode: node,
          onSubtitleSelected: (_) {},
          onLoadLocal: () {},
          onClose: () {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();
    expect(_rowHoldsNode(tester, node, '英字'), isTrue,
        reason: '落焦当前生效的字幕轨，无需从头翻');
    expect(_rowHoldsNode(tester, node, '关闭字幕'), isFalse);
  });

  testWidgets('TV：音轨面板落焦选中音轨行', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '音轨',
        child: AudioTrackMenuPanel(
          player: _FakePlayer(audioTracks: const [1]),
          audioStreams: [
            _stream('Audio', 0, label: '国语'),
            _stream('Audio', 1, label: '英语'),
          ],
          focusNode: node,
          onAudioSelected: (_) {},
          onClose: () {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();
    expect(_rowHoldsNode(tester, node, '英语'), isTrue);
    expect(_rowHoldsNode(tester, node, '国语'), isFalse);
  });

  testWidgets('TV：音轨空列表节点未挂树，requestFocus 不抛（deferred 守卫）', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '音轨',
        child: AudioTrackMenuPanel(
          player: _FakePlayer(),
          audioStreams: const [],
          focusNode: node,
          onAudioSelected: (_) {},
          onClose: () {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();
    expect(node.enclosingScope, isNull, reason: '无行可挂，节点不进焦点树');
    expect(tester.takeException(), isNull);
    node.requestFocus(); // 未挂树：置 deferred 标记，不抛
    await tester.pump();
    expect(node.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}

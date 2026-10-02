import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/decode_mode_panel.dart';
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

    expect(find.text('智能'), findsOneWidget);
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
}

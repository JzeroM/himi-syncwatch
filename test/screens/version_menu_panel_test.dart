import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/version_menu_panel.dart';

import '../helpers/test_fakes.dart';

void main() {
  final sources = [
    MediaSource(id: 'a', name: '1080p版', width: 1920, bitrate: 2000000),
    MediaSource(id: 'b', name: '4K版', width: 3840, bitrate: 8000000),
  ];

  Widget wrap({
    required String? activeId,
    required ValueChanged<MediaSource> onSelected,
    required VoidCallback onClose,
  }) {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings())),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 400,
            child: VersionMenuPanel(
              sources: sources,
              activeSourceId: activeId,
              onSourceSelected: onSelected,
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('渲染全部版本行，name 作为标签', (tester) async {
    await tester.pumpWidget(wrap(
      activeId: 'b',
      onSelected: (_) {},
      onClose: () {},
    ));
    await tester.pump();
    expect(find.textContaining('1080p版'), findsOneWidget);
    expect(find.textContaining('4K版'), findsOneWidget);
  });

  testWidgets('当前生效版本行带选中对勾', (tester) async {
    await tester.pumpWidget(wrap(
      activeId: 'a',
      onSelected: (_) {},
      onClose: () {},
    ));
    await tester.pump();
    // 选中行只有一个对勾图标
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('点某版本 → 回调该源并请求关闭', (tester) async {
    MediaSource? picked;
    var closed = false;
    await tester.pumpWidget(wrap(
      activeId: 'b',
      onSelected: (s) => picked = s,
      onClose: () => closed = true,
    ));
    await tester.pump();

    await tester.tap(find.textContaining('1080p版'));
    await tester.pump();
    expect(picked?.id, 'a');
    expect(closed, isTrue);
  });

  testWidgets('无版本时展示空态', (tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings())),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 400,
              child: VersionMenuPanel(
                sources: const [],
                activeSourceId: null,
                onSourceSelected: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('当前视频无其他版本'), findsOneWidget);
  });
}

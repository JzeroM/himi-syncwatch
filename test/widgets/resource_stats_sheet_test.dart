import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/library_counts.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/resource_stats_sheet.dart';

import '../helpers/test_fakes.dart';

/// 测试用已认证服务器配置。
EmbyServerConfig _server({String id = 'srv-1'}) => EmbyServerConfig(
      id: id,
      serverUrl: 'http://127.0.0.1:8096',
      serverName: '测试服',
      serverId: 'emby-1',
      username: 'tester',
      accessToken: 'tok',
      userId: 'u1',
    );

Widget _pump({
  required EmbyServerConfig server,
  required FakeEmbyService service,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(const AppSettings(glassUi: false)),
      ),
      embyServerListProvider.overrideWith((ref) {
        final n = EmbyServerListNotifier();
        n.setList([server]);
        return n;
      }),
      embyServiceFactoryProvider.overrideWith((ref) => (_) => service),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showResourceStatsSheet(context, server),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const without = MediaCounts(movies: 10, series: 20, episodes: 30);
  const withV = MediaCounts(movies: 11, series: 21, episodes: 31);

  testWidgets('打开即懒加载，展示不含/包含多版本计数', (tester) async {
    final service = FakeEmbyService()
      ..libraryCounts = const LibraryCounts(
        withoutVersions: without,
        withVersions: withV,
      );

    await tester.pumpWidget(_pump(server: _server(), service: service));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('测试服'), findsOneWidget);
    expect(find.text('不含多版本'), findsOneWidget);
    expect(find.text('包含多版本'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('剧集'), findsOneWidget);
    expect(find.text('集'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('加载失败（null）显示空态文案', (tester) async {
    final service = FakeEmbyService(); // libraryCounts = null

    await tester.pumpWidget(_pump(server: _server(), service: service));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('未能获取统计信息'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('关闭按钮关闭面板', (tester) async {
    final service = FakeEmbyService()
      ..libraryCounts = const LibraryCounts(
        withoutVersions: without,
        withVersions: withV,
      );

    await tester.pumpWidget(_pump(server: _server(), service: service));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resourceStatsClose')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('resourceStatsClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resourceStatsClose')), findsNothing);
  });
}

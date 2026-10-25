import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/widgets/trakt/trakt_sync_status_panel.dart';

Widget _panel({
  required TraktSyncState state,
  TraktSyncProgress? live,
  bool syncing = false,
  VoidCallback? onSync,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TraktSyncStatusPanel(
          syncState: state,
          live: live,
          syncing: syncing,
          onSync: onSync ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('面板显示总量与上次成功时间', (tester) async {
    await tester.pumpWidget(_panel(
      state: TraktSyncState(
        lastSuccessAt: DateTime.utc(2026, 1, 1, 12),
        movies: 12,
        shows: 3,
        episodes: 40,
      ),
    ));

    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('已同步'), findsOneWidget);
    expect(find.text('同步失败'), findsNothing);
  });

  testWidgets('同步中显示阶段与服务器进度', (tester) async {
    await tester.pumpWidget(_panel(
      state: const TraktSyncState(movies: 1),
      live: const TraktSyncProgress(
        phase: TraktSyncPhase.scanningServers,
        serversDone: 1,
        serversTotal: 3,
      ),
      syncing: true,
    ));

    expect(find.text('同步中'), findsOneWidget);
    expect(find.text('扫描服务器 1/3'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('点击立即同步触发回调', (tester) async {
    var called = 0;
    await tester.pumpWidget(_panel(
      state: const TraktSyncState(),
      onSync: () => called++,
    ));

    await tester.tap(find.text('立即同步'));
    await tester.pump();

    expect(called, 1);
  });
}

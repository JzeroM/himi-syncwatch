import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/cache_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/cache_settings_screen.dart';
import 'package:himi_syncwatch/services/cache/cache_models.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

import '../helpers/cache_fakes.dart';
import '../helpers/test_fakes.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAppCacheService service, {
    bool tvMode = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(overrides: [
      appCacheServiceProvider.overrideWithValue(service),
      settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(AppSettings(tvMode: tvMode)),
      ),
    ]);
    addTearDown(container.dispose);

    final page = MaterialApp(home: const CacheSettingsScreen());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: tvMode ? TvRemoteShell(child: page) : page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('缓存列表按图片、弹幕、临时文件、诊断日志排序', (tester) async {
    await pumpScreen(
      tester,
      FakeAppCacheService(
          cacheSnapshot(images: 100, danmaku: 3, temp: 50, logs: 20)),
    );

    final keys = [
      for (final category in CacheCategory.values)
        ValueKey('cacheRow_${category.name}'),
    ];
    final ys = [for (final key in keys) tester.getTopLeft(find.byKey(key)).dy];
    for (var i = 0; i < ys.length - 1; i++) {
      expect(ys[i], lessThan(ys[i + 1]), reason: '缓存分类顺序错误');
    }
    expect(find.text('弹幕缓存 3 条（内存）'), findsOneWidget);
  });

  testWidgets('总缓存只统计磁盘分类，不含弹幕条数', (tester) async {
    await pumpScreen(
      tester,
      FakeAppCacheService(
        cacheSnapshot(
            images: 1024 * 1024, danmaku: 7, temp: 512 * 1024, logs: 1024),
      ),
    );

    final total = tester.widget<Text>(
      find.byKey(const ValueKey('cacheTotalSize')),
    );
    expect(total.data, '1.50 MB');
    expect(find.text('弹幕缓存 7 条（内存）'), findsOneWidget);
  });

  testWidgets('单类清理需确认，取消不清理', (tester) async {
    final service = FakeAppCacheService(
        cacheSnapshot(images: 100, danmaku: 1, temp: 10, logs: 5));
    await pumpScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('cacheClear_images')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tvConfirmCancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tvConfirmCancel')));
    await tester.pumpAndSettle();
    expect(service.cleared, isEmpty);

    await tester.tap(find.byKey(const ValueKey('cacheClear_images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tvConfirmOk')));
    await tester.pumpAndSettle();
    expect(service.cleared, [CacheCategory.images]);
  });

  testWidgets('清理全部清理四类并刷新为 0 B', (tester) async {
    final service = FakeAppCacheService(
        cacheSnapshot(images: 100, danmaku: 2, temp: 10, logs: 5));
    await pumpScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('cacheClearAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tvConfirmOk')));
    await tester.pumpAndSettle();

    expect(service.clearAllCount, 1);
    final total = tester.widget<Text>(
      find.byKey(const ValueKey('cacheTotalSize')),
    );
    expect(total.data, '0 B');
  });

  testWidgets('空缓存时删除与清理全部均禁用', (tester) async {
    await pumpScreen(tester, FakeAppCacheService(cacheSnapshot()));

    final delete = tester.widget<IconButton>(
      find.byKey(const ValueKey('cacheClear_images')),
    );
    expect(delete.onPressed, isNull);
    final clearAll = tester.widget<TvFocusable>(
      find.byKey(const ValueKey('cacheClearAll')),
    );
    expect(clearAll.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('cacheClearAll')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('扫描失败显示错误并可重试', (tester) async {
    final service = FakeAppCacheService(cacheSnapshot())..failScan = true;
    await pumpScreen(tester, service);

    expect(find.text('读取缓存信息失败'), findsOneWidget);
    service.failScan = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cacheTotalSize')), findsOneWidget);
  });

  testWidgets('TV 模式确认弹层默认聚焦取消', (tester) async {
    final service = FakeAppCacheService(cacheSnapshot(images: 100));
    await pumpScreen(tester, service, tvMode: true);

    await tester.tap(find.byKey(const ValueKey('cacheRow_images')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(service.cleared, isEmpty);
  });

  testWidgets('TV 模式方向键右移后 Enter 执行清理', (tester) async {
    final service = FakeAppCacheService(cacheSnapshot(images: 100));
    await pumpScreen(tester, service, tvMode: true);

    await tester.tap(find.byKey(const ValueKey('cacheRow_images')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(service.cleared, [CacheCategory.images]);
  });
}

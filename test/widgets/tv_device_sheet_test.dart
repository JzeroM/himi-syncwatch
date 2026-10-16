import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/services/tv_sync/paired_tv_store.dart';
import 'package:himi_syncwatch/widgets/swipe_reveal_action.dart';
import 'package:himi_syncwatch/widgets/tv_device_sheet.dart';

import '../helpers/test_fakes.dart';

/// 固定返回预置配对 TV 的 store（不触碰 secure storage）。
class _StaticPairedTvStore extends PairedTvStore {
  _StaticPairedTvStore(this._tv);
  final PairedTv? _tv;

  @override
  Future<PairedTv?> load() async => _tv;

  @override
  Future<void> save(PairedTv tv) async {}

  @override
  Future<void> clear() async {}
}

/// 不启动真实 UDP 监听、直接返回预置设备的发现 notifier。
class _FakeDiscoveryNotifier extends TvDiscoveryNotifier {
  _FakeDiscoveryNotifier(Map<String, TvDeviceInfo> devices) {
    state = devices;
  }

  @override
  Future<void> start() async {}
}

TvDeviceInfo _device(String id, String name, String ip, [int port = 17894]) =>
    TvDeviceInfo(deviceId: id, name: name, ip: ip, httpPort: port);

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required Map<String, TvDeviceInfo> devices,
  PairedTv? paired,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(const AppSettings()),
      ),
      tvDiscoveryProvider.overrideWith((ref) => _FakeDiscoveryNotifier(devices)),
      pairedTvProvider.overrideWith(
        (ref) => PairedTvNotifier(store: _StaticPairedTvStore(paired)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showTvDeviceSheet(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('已配对设备左滑露出「取消配对」，点按后清除配对', (tester) async {
    final container = await _pumpSheet(
      tester,
      devices: {
        'tv_1': _device('tv_1', '客厅电视', '192.168.1.10'),
      },
      paired: const PairedTv(
        deviceId: 'tv_1',
        name: '客厅电视',
        ip: '192.168.1.10',
        port: 17894,
        token: 'tok',
      ),
    );

    // 已配对行被滑动组件包裹
    expect(find.byType(SwipeRevealAction), findsOneWidget);
    expect(container.read(pairedTvProvider), isNotNull);

    await tester.drag(
        find.byType(SwipeRevealAction), const Offset(-200, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消配对'));
    await tester.pumpAndSettle();

    expect(container.read(pairedTvProvider), isNull, reason: '取消配对应清除本地配对');
    expect(find.textContaining('已取消配对'), findsWidgets);
  });

  testWidgets('未配对设备不提供左滑取消配对', (tester) async {
    await _pumpSheet(
      tester,
      devices: {
        'tv_2': _device('tv_2', '卧室电视', '192.168.1.20'),
      },
    );

    expect(find.byType(SwipeRevealAction), findsNothing);
    expect(find.text('配对'), findsWidgets);
  });

  testWidgets('已配对但离线（不在发现列表）→ 不显示该设备', (tester) async {
    await _pumpSheet(
      tester,
      devices: {
        'tv_2': _device('tv_2', '卧室电视', '192.168.1.20'),
      },
      paired: const PairedTv(
        deviceId: 'tv_1',
        name: '客厅电视',
        ip: '192.168.1.10',
        port: 17894,
        token: 'tok',
      ),
    );

    expect(find.text('客厅电视'), findsNothing, reason: '离线已配对设备不显示');
    expect(find.byType(SwipeRevealAction), findsNothing);
  });
}

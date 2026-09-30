import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _config(String id, {bool authenticated = true}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: '服务器$id',
    serverId: 'srv-$id',
    username: 'user',
    accessToken: authenticated ? 'token' : null,
    userId: authenticated ? 'uid' : null,
  );
}

void main() {
  group('embyConfigForProvider / embyServiceForProvider', () {
    late ProviderContainer container;
    final current = _config('current');
    final other = _config('other');
    final guest = _config('guest', authenticated: false);
    late List<EmbyServerConfig> built;

    setUp(() {
      built = [];
      container = ProviderContainer(
        overrides: [
          embyServiceFactoryProvider.overrideWithValue((server) {
            built.add(server);
            return FakeEmbyService();
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(embyConfigProvider.notifier).setConfig(current);
      container
          .read(embyServerListProvider.notifier)
          .setList([current, other, guest]);
      // 预热当前服务（embyServiceProvider 也走 factory），避免污染 built 断言
      container.read(embyServiceProvider);
      built.clear();
    });

    test('null/空 serverId 解析为当前激活配置与单例服务', () {
      expect(container.read(embyConfigForProvider(null)), same(current));
      expect(container.read(embyConfigForProvider('')), same(current));
      expect(
        container.read(embyServiceForProvider(null)),
        same(container.read(embyServiceProvider)),
      );
      expect(
        container.read(embyServiceForProvider('')),
        same(container.read(embyServiceProvider)),
      );
      expect(built, isEmpty);
    });

    test('与当前激活同 id 时复用当前服务单例', () {
      expect(container.read(embyConfigForProvider('current')), same(current));
      expect(
        container.read(embyServiceForProvider('current')),
        same(container.read(embyServiceProvider)),
      );
      expect(built, isEmpty);
    });

    test('列表内其他已认证服务器按配置独立构建', () {
      expect(container.read(embyConfigForProvider('other')), same(other));

      final service = container.read(embyServiceForProvider('other'));
      expect(built, [other]);
      expect(
        service,
        same(container.read(embyServiceForProvider('other'))),
        reason: '同一 serverId 应缓存同一实例',
      );
      expect(
        service,
        isNot(same(container.read(embyServiceProvider))),
      );
    });

    test('未认证服务器回退当前激活服务', () {
      expect(container.read(embyConfigForProvider('guest')), same(guest));
      expect(
        container.read(embyServiceForProvider('guest')),
        same(container.read(embyServiceProvider)),
      );
      expect(built, isEmpty);
    });

    test('未知 serverId 回退当前激活配置与服务', () {
      expect(container.read(embyConfigForProvider('missing')), same(current));
      expect(
        container.read(embyServiceForProvider('missing')),
        same(container.read(embyServiceProvider)),
      );
      expect(built, isEmpty);
    });
  });
}

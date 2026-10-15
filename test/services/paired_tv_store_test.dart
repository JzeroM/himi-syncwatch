import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/services/tv_sync/paired_tv_store.dart';

/// 内存版 FlutterSecureStorage（只覆写用到的三个方法）。
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSecureStorage storage;
  late PairedTvStore store;

  setUp(() {
    storage = FakeSecureStorage();
    store = PairedTvStore(storage: storage);
  });

  const token32 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const tv = PairedTv(
    deviceId: 'tv_1',
    name: '客厅电视',
    ip: '192.168.1.10',
    port: 17894,
    token: token32,
  );

  test('save 后 load 还原；clear 后为 null', () async {
    await store.save(tv);
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.deviceId, 'tv_1');
    expect(loaded.name, '客厅电视');
    expect(loaded.ip, '192.168.1.10');
    expect(loaded.port, 17894);
    expect(loaded.token, 'a' * 32);
    expect(loaded.baseUrl, 'http://192.168.1.10:17894');

    await store.clear();
    expect(await store.load(), isNull);
  });

  test('未存过 → load 返回 null', () async {
    expect(await store.load(), isNull);
  });

  test('损坏 JSON → load 返回 null 不抛', () async {
    storage.data['himi_paired_tv'] = '{broken';
    expect(await store.load(), isNull);
  });

  test('deviceId/token 为空视为无效 → load 返回 null', () async {
    storage.data['himi_paired_tv'] =
        '{"deviceId":"","name":"x","ip":"1.1.1.1","port":1,"token":"t"}';
    expect(await store.load(), isNull);

    storage.data['himi_paired_tv'] =
        '{"deviceId":"tv","name":"x","ip":"1.1.1.1","port":1,"token":""}';
    expect(await store.load(), isNull);
  });

  test('PairedTv.fromDevice 从发现结果构造', () {
    final device = TvDeviceInfo(
      deviceId: 'tv_9',
      name: '书房TV',
      ip: '192.168.1.20',
      httpPort: 17900,
    );
    final paired = PairedTv.fromDevice(device, 'tok123');
    expect(paired.deviceId, 'tv_9');
    expect(paired.name, '书房TV');
    expect(paired.baseUrl, 'http://192.168.1.20:17900');
    expect(paired.token, 'tok123');
    expect(paired.toJson()['port'], 17900);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/update/update_package_cleaner.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('himi_update_cleaner_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeUpdate(String name) async {
    final file = File(
      '${temp.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}$name',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [1, 2, 3]);
    return file;
  }

  test('只删除已安装版本及更旧更新包', () async {
    final installedApk = await writeUpdate('himi-sync-1.2.36-arm64-v8a.apk');
    final olderSetup = await writeUpdate('himi-sync-windows-1.2.35-setup.exe');
    final installedIpa = await writeUpdate('himi-sync-ios-unsigned-1.2.36.ipa');
    final pending = await writeUpdate('himi-sync-1.2.37-arm64-v8a.apk');
    final other = await writeUpdate('other.bin');

    final removed = await UpdatePackageCleaner(
      temporaryDirectory: () async => temp,
    ).cleanup(currentVersion: '1.2.36');

    expect(removed, 3);
    expect(await installedApk.exists(), isFalse);
    expect(await olderSetup.exists(), isFalse);
    expect(await installedIpa.exists(), isFalse);
    expect(await pending.exists(), isTrue);
    expect(await other.exists(), isTrue);
  });

  test('版本无法解析时保留文件', () async {
    final broken = await writeUpdate('himi-sync-broken.apk');

    final removed = await UpdatePackageCleaner(
      temporaryDirectory: () async => temp,
    ).cleanup(currentVersion: '1.2.36');

    expect(removed, 0);
    expect(await broken.exists(), isTrue);
  });

  test('当前版本为空时不做删除', () async {
    final installed = await writeUpdate('himi-sync-1.2.36-arm64-v8a.apk');

    final removed = await UpdatePackageCleaner(
      temporaryDirectory: () async => temp,
    ).cleanup(currentVersion: '  ');

    expect(removed, 0);
    expect(await installed.exists(), isTrue);
  });

  test('updates 目录不存在时返回 0', () async {
    final removed = await UpdatePackageCleaner(
      temporaryDirectory: () async => temp,
    ).cleanup(currentVersion: '1.2.36');

    expect(removed, 0);
  });
}

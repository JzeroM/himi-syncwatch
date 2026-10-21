import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/manual_segment_store.dart';

void main() {
  late Directory dir;
  late LocalManualSegmentStore store;
  var nowMs = 1000;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('himi_manual_segments_');
    store = LocalManualSegmentStore(
      directory: dir.path,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs++),
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('无文件时返回 null，不抛错', () async {
    expect(await store.get('s1|series-1'), isNull);
  });

  test('设置片头后重新读取仍存在（持久化）', () async {
    await store.setIntroEnd(
      key: 's1|series-1',
      serverId: 's1',
      seriesId: 'series-1',
      itemId: 'ep-1',
      providerIds: const {'Tvdb': '42'},
      introEndMs: 90000,
    );

    final again = LocalManualSegmentStore(directory: dir.path);
    final record = await again.get('s1|series-1');
    expect(record, isNotNull);
    expect(record!.introEndMs, 90000);
    expect(record.seriesId, 'series-1');
    expect(record.providerIds, {'Tvdb': '42'});
    expect(
      File('${dir.path}/${LocalManualSegmentStore.fileName}').existsSync(),
      isTrue,
    );
  });

  test('片头与片尾可分别更新，清除一项保留另一项', () async {
    await store.setIntroEnd(
      key: 's1|m1',
      serverId: 's1',
      itemId: 'm1',
      introEndMs: 1000,
    );
    await store.setCreditsStart(
      key: 's1|m1',
      serverId: 's1',
      itemId: 'm1',
      creditsStartMs: 5000,
    );

    var record = await store.get('s1|m1');
    expect(record!.introEndMs, 1000);
    expect(record.creditsStartMs, 5000);

    await store.clearIntro('s1|m1');
    record = await store.get('s1|m1');
    expect(record!.introEndMs, isNull);
    expect(record.creditsStartMs, 5000);

    await store.clearCredits('s1|m1');
    expect(await store.get('s1|m1'), isNull);
  });

  test('损坏 JSON 按空数据处理', () async {
    await File('${dir.path}/${LocalManualSegmentStore.fileName}')
        .writeAsString('not json');
    expect(await store.get('s1|m1'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_store.dart';

import '../helpers/fake_secure_storage.dart';

void main() {
  late FakeSecureStorage storage;
  late TraktSyncStore store;

  setUp(() {
    storage = FakeSecureStorage();
    store = TraktSyncStore(storage: storage);
  });

  test('成功同步持久化总量与时间', () async {
    final success = await store.recordSuccess(
      const TraktSyncStatistics(movies: 7, shows: 2, episodes: 20),
    );
    expect(success.movies, 7);
    expect(success.shows, 2);
    expect(success.episodes, 20);
    expect(success.lastSuccessAt, isNotNull);

    final reread = await store.read();
    expect(reread.movies, 7);
    expect(reread.shows, 2);
    expect(reread.episodes, 20);
    expect(reread.lastSuccessAt, isNotNull);
  });
}

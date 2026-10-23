import 'dart:math';

import 'package:himi_syncwatch/services/image_size_probe.dart';

class HeroImageCandidate<T> {
  const HeroImageCandidate({
    required this.value,
    required this.url,
    this.accessToken,
  });

  final T value;
  final String url;
  final String? accessToken;
}

class HeroImageSelector {
  const HeroImageSelector({
    required this.probe,
    this.minWidth = 1920,
    this.limit = 6,
    this.batchSize = 4,
  });

  final ImageSizeProbe probe;
  final int minWidth;
  final int limit;
  final int batchSize;

  Future<List<T>> select<T>(
    Iterable<HeroImageCandidate<T>> candidates, {
    required int seed,
  }) async {
    final ranked =
        candidates.where((candidate) => candidate.url.isNotEmpty).toList();
    ranked.shuffle(Random(seed));

    final selected = <T>[];
    for (var start = 0;
        start < ranked.length && selected.length < limit;
        start += batchSize) {
      final batch = ranked.skip(start).take(batchSize).toList(growable: false);
      final sizes = await Future.wait([
        for (final candidate in batch)
          probe.probe(candidate.url, accessToken: candidate.accessToken),
      ]);
      for (var i = 0; i < batch.length && selected.length < limit; i++) {
        final size = sizes[i];
        if (size != null && size.width >= minWidth) {
          selected.add(batch[i].value);
        }
      }
    }
    return selected;
  }
}

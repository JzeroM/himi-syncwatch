import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/hero_image_selector.dart';
import 'package:himi_syncwatch/services/image_size_probe.dart';

class _FakeImageSizeProbe extends ImageSizeProbe {
  _FakeImageSizeProbe(this.sizes);

  final Map<String, ImageSize?> sizes;

  @override
  Future<ImageSize?> probe(String url, {String? accessToken}) async =>
      sizes[url];
}

HeroImageCandidate<String> _candidate(int id) =>
    HeroImageCandidate(value: '$id', url: 'https://s1/$id.jpg');

void main() {
  test('过滤低清并限制最多 6 条', () async {
    final candidates = [
      for (var i = 0; i < 10; i++) _candidate(i),
    ];
    final sizes = {
      for (final candidate in candidates)
        candidate.url: candidate.value == '0'
            ? const ImageSize(1280, 720)
            : const ImageSize(3840, 2160),
    };
    final selector = HeroImageSelector(probe: _FakeImageSizeProbe(sizes));

    final selected = await selector.select(candidates, seed: 7);

    expect(selected, hasLength(6));
    expect(selected, isNot(contains('0')));
  });

  test('相同种子结果稳定，不同种子结果不同', () async {
    final candidates = [
      for (var i = 0; i < 20; i++) _candidate(i),
    ];
    final sizes = {
      for (final candidate in candidates)
        candidate.url: const ImageSize(3840, 2160),
    };
    final selector = HeroImageSelector(probe: _FakeImageSizeProbe(sizes));

    final first = await selector.select(candidates, seed: 1);
    final again = await selector.select(candidates, seed: 1);
    final other = await selector.select(candidates, seed: 2);

    expect(again, first);
    expect(other, isNot(first));
  });

  test('探测失败视为不合格', () async {
    final candidates = [_candidate(1), _candidate(2)];
    final selector = HeroImageSelector(
      probe: _FakeImageSizeProbe({
        candidates[0].url: const ImageSize(3840, 2160),
        candidates[1].url: null,
      }),
    );

    final selected = await selector.select(candidates, seed: 3);
    expect(selected, ['1']);
  });
}

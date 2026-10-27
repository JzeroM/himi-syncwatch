import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/adapters/nipa_media_kit_adapter.dart'
    show isHdrVideoParams;
import 'package:media_kit/media_kit.dart';

void main() {
  test('Windows libplacebo 滤镜只对 HDR/DoVi 生效', () {
    expect(
      isHdrVideoParams(const VideoParams(gamma: 'pq', primaries: 'bt.2020')),
      isTrue,
    );
    expect(isHdrVideoParams(const VideoParams(gamma: 'hlg')), isTrue);
    expect(
      isHdrVideoParams(const VideoParams(gamma: 'smpte2084')),
      isTrue,
    );
    expect(
      isHdrVideoParams(
          const VideoParams(gamma: 'bt.1886', primaries: 'bt.709')),
      isFalse,
    );
  });
}

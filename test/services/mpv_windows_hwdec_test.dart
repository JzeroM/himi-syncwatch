import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';
import 'package:himi_syncwatch/services/player/mpv_player_adapter.dart';

void main() {
  group('resolveWindowsHwdec', () {
    test('Windows auto 使用 copy-back，避免 d3d11 零拷贝崩溃', () {
      expect(resolveWindowsHwdec('auto', windows: true), 'auto-copy');
      expect(resolveWindowsHwdec('ohcodec', windows: true), 'auto-copy');
    });

    test('Windows 纯软解保持 no', () {
      expect(resolveWindowsHwdec('no', windows: true), 'no');
    });

    test('非 Windows 不转换', () {
      expect(resolveWindowsHwdec('auto', windows: false), 'auto');
      expect(resolveWindowsHwdec('ohcodec', windows: false), 'ohcodec');
    });
  });

  group('redactWindowsMpvLog', () {
    test('URL query 与 header token 都脱敏', () {
      const input =
          'Set property: http-header-fields=["X-Emby-Token: secret-token"] '
          'open https://example.com/video?api_key=secret-key&x=1';
      final output = redactWindowsMpvLog(input);
      final bearer = redactWindowsMpvLog('Authorization: Bearer secret-bearer');

      expect(output, isNot(contains('secret-token')));
      expect(output, isNot(contains('secret-key')));
      expect(output, contains('X-Emby-Token: <redacted>'));
      expect(bearer, isNot(contains('secret-bearer')));
      expect(bearer, contains('Authorization: <redacted>'));
    });
  });
}

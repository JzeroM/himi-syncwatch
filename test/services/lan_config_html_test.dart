import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/lan_config/lan_config_html.dart';

void main() {
  String html({String mode = ''}) => buildLanConfigHtml(
        ips: ['192.168.1.5'],
        port: 8096,
        token: 'tok',
        mode: mode,
      );

  test('mode 为空：两区块全显（旧链接兼容）', () {
    final text = html();
    expect(text, contains('<section id="emby">'));
    expect(text, contains('<section id="agora">'));
    expect(text, contains('emby_url'));
    expect(text, contains('agora_id'));
  });

  test('mode=emby：只保留 Emby 配置，不出现声网区块', () {
    // TV 扫码配置只配 Emby——页面不得出现声网配置入口
    final text = html(mode: 'emby');
    expect(text, contains('<section id="emby">'));
    expect(text, contains('emby_url'));
    expect(text, isNot(contains('<section id="agora">')));
    expect(text, isNot(contains('agora_id')));
    expect(text, isNot(contains('submitAgora()')));
    // 高亮滚动仍指向 emby
    expect(text, contains("highlight('emby')"));
  });

  test('mode=agora：只保留声网配置，不出现 Emby 区块', () {
    final text = html(mode: 'agora');
    expect(text, contains('<section id="agora">'));
    expect(text, contains('agora_id'));
    expect(text, isNot(contains('<section id="emby">')));
    expect(text, isNot(contains('emby_url')));
    expect(text, isNot(contains('submitEmby()')));
    expect(text, contains("highlight('agora')"));
  });

  test('页脚备选链接带 token（各 mode 均保留）', () {
    for (final mode in ['', 'emby', 'agora']) {
      expect(html(mode: mode), contains('http://192.168.1.5:8096/?t=tok'));
    }
  });
}

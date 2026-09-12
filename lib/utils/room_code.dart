import 'dart:convert';
import 'dart:math';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:uuid/uuid.dart';

class RoomCode {
  static const String _prefix = 'HIMI:';

  static String encode({
    required String appId,
    required String appCertificate,
    required String channel,
    int tokenCount = 2,
    int tokenExpireSeconds = 86400,
  }) {
    final tokens = <Map<String, dynamic>>[];
    for (int i = 0; i < tokenCount; i++) {
      final tokenId = 'himi_${const Uuid().v4().substring(0, 8)}';
      final token = RtmTokenBuilder.buildToken(
        appId: appId,
        appCertificate: appCertificate,
        userId: tokenId,
        tokenExpireSeconds: tokenExpireSeconds,
      );
      tokens.add({'i': tokenId, 'r': token});
    }

    final data = {
      'v': 1,
      'appId': appId,
      'channel': channel,
      't': tokens,
    };

    final encoded = base64Url.encode(utf8.encode(jsonEncode(data)));
    return '$_prefix$encoded';
  }

  static Map<String, dynamic>? decode(String code) {
    if (!code.startsWith(_prefix)) return null;

    try {
      final payload = code.substring(_prefix.length);
      final decoded = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;

      if (data['v'] != 1) return null;
      if (data['appId'] == null || data['channel'] == null) return null;
      if (data['t'] is! List) return null;

      data['tokens'] = data['t'];
      for (final t in data['tokens']) {
        if (t is Map) {
          t['tokenId'] = t['i'];
          t['token'] = t['r'];
        }
      }

      return data;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? consumeToken(Map<String, dynamic> roomData) {
    final tokens = roomData['tokens'] as List?;
    if (tokens == null || tokens.isEmpty) return null;

    final rng = Random();
    final index = rng.nextInt(tokens.length);
    final item = tokens.removeAt(index);
    return Map<String, dynamic>.from(item);
  }

  static String generateChannelId() {
    return 'himi_${const Uuid().v4().substring(0, 12)}';
  }
}

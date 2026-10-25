class TraktConfig {
  static const _injectedClientId =
      String.fromEnvironment('TRAKT_CLIENT_ID', defaultValue: '');

  final String clientId;
  final String redirectUri;
  final String apiBase;
  final String authorizeUrl;
  final List<String> tokenUrls;
  final String deviceCodeUrl;
  final String deviceTokenUrl;
  final List<String> revokeUrls;
  final String userAgent;

  const TraktConfig({
    this.clientId = _injectedClientId,
    this.redirectUri = 'https://track.seraphine.eu.org/oauth/trakt/',
    this.apiBase = 'https://api.trakt.tv',
    this.authorizeUrl = 'https://trakt.tv/oauth/authorize',
    this.tokenUrls = const [
      'https://auth.trakt.tv/oauth/token',
      'https://api.trakt.tv/oauth/token',
    ],
    this.deviceCodeUrl = 'https://auth.trakt.tv/oauth/device/code',
    this.deviceTokenUrl = 'https://auth.trakt.tv/oauth/device/token',
    this.revokeUrls = const [
      'https://auth.trakt.tv/oauth/revoke',
      'https://api.trakt.tv/oauth/revoke',
    ],
    this.userAgent = 'HIMI/1.4.0',
  });

  bool get isConfigured => clientId.trim().isNotEmpty;

  static const callbackScheme = 'himi';
  static const callbackHost = 'oauth';
  static const callbackPath = '/trakt';

  Uri buildAuthorizeUri({
    required String state,
    required String codeChallenge,
  }) {
    return Uri.parse(authorizeUrl).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
  }
}

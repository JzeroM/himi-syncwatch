import 'dart:convert';

class TraktTokens {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime expiresAt;
  final DateTime createdAt;

  const TraktTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  bool isExpiringWithin(Duration duration, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return !expiresAt.isAfter(at.add(duration));
  }

  factory TraktTokens.fromResponse(
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 0;
    final createdAtRaw = json['created_at'];
    final createdAt = createdAtRaw is num
        ? DateTime.fromMillisecondsSinceEpoch(createdAtRaw.toInt() * 1000)
        : at;
    return TraktTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAt: createdAt.add(Duration(seconds: expiresIn)),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'token_type': tokenType,
        'expires_at': expiresAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory TraktTokens.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? value) =>
        DateTime.tryParse(value ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return TraktTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAt: parse(json['expires_at'] as String?),
      createdAt: parse(json['created_at'] as String?),
    );
  }

  @override
  String toString() =>
      'TraktTokens(accessToken: <redacted>, expiresAt: $expiresAt)';
}

class TraktPkceSession {
  final String verifier;
  final String state;
  final DateTime createdAt;

  const TraktPkceSession({
    required this.verifier,
    required this.state,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'verifier': verifier,
        'state': state,
        'created_at': createdAt.toIso8601String(),
      };

  factory TraktPkceSession.fromJson(Map<String, dynamic> json) {
    return TraktPkceSession(
      verifier: json['verifier'] as String? ?? '',
      state: json['state'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool isExpired(
      {DateTime? now, Duration maxAge = const Duration(minutes: 10)}) {
    final at = now ?? DateTime.now();
    return at.difference(createdAt) > maxAge;
  }
}

class TraktDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int interval;

  const TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory TraktDeviceCode.fromJson(Map<String, dynamic> json) {
    return TraktDeviceCode(
      deviceCode: json['device_code'] as String? ?? '',
      userCode: json['user_code'] as String? ?? '',
      verificationUrl:
          json['verification_url'] as String? ?? 'https://trakt.tv/activate',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 600,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }
}

class TraktAccount {
  final String username;
  final String name;
  final int? id;

  const TraktAccount({
    required this.username,
    required this.name,
    this.id,
  });

  factory TraktAccount.fromJson(Map<String, dynamic> json) {
    final ids = json['ids'];
    return TraktAccount(
      username: json['username'] as String? ?? '',
      name: json['name'] as String? ?? '',
      id: ids is Map ? (ids['trakt'] as num?)?.toInt() : null,
    );
  }
}

class TraktDevicePollResult {
  final TraktDevicePollStatus status;
  final TraktTokens? tokens;
  final String? message;

  const TraktDevicePollResult._(this.status, {this.tokens, this.message});

  const TraktDevicePollResult.success(TraktTokens tokens)
      : this._(TraktDevicePollStatus.success, tokens: tokens);

  const TraktDevicePollResult.pending() : this._(TraktDevicePollStatus.pending);

  const TraktDevicePollResult.slowDown()
      : this._(TraktDevicePollStatus.slowDown);

  const TraktDevicePollResult.failure(
    TraktDevicePollStatus status, [
    String? message,
  ]) : this._(status, message: message);
}

enum TraktDevicePollStatus {
  success,
  pending,
  slowDown,
  invalid,
  used,
  expired,
  denied,
  error,
}

class TraktMediaIds {
  final int? trakt;
  final int? tmdb;
  final int? tvdb;
  final String? imdb;

  const TraktMediaIds({this.trakt, this.tmdb, this.tvdb, this.imdb});

  factory TraktMediaIds.fromJson(Map<String, dynamic> json) {
    final tmdb = json['tmdb'];
    final tvdb = json['tvdb'];
    return TraktMediaIds(
      trakt: (json['trakt'] as num?)?.toInt(),
      tmdb: tmdb is num ? tmdb.toInt() : null,
      tvdb: tvdb is num ? tvdb.toInt() : null,
      imdb: json['imdb'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (trakt != null) 'trakt': trakt,
        if (tmdb != null) 'tmdb': tmdb,
        if (tvdb != null) 'tvdb': tvdb,
        if (imdb != null && imdb!.isNotEmpty) 'imdb': imdb,
      };
}

String traktJsonEncode(Object? value) => jsonEncode(value);

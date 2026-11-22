import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/bridge_parsers.dart';
import 'package:himi_syncwatch/services/ratings_cache_store.dart';

/// 拉取原始响应体（可注入便于测试；默认走 Dio）。
typedef RatingsHttpGet = Future<String> Function(
  Uri url, {
  Map<String, String> headers,
});

/// 挑战 POST（表单提交）结果：body + Set-Cookie（豆瓣通行凭证）。
class RatingsHttpPostResult {
  const RatingsHttpPostResult({this.body = '', this.setCookie});

  final String body;

  /// 响应 `Set-Cookie` 原文（多条以 `\n` 连接）；无则 null。
  final String? setCookie;
}

/// 表单 POST（可注入便于测试；默认走 Dio，不跟随重定向以直读 Set-Cookie）。
typedef RatingsHttpPost = Future<RatingsHttpPostResult> Function(
  Uri url, {
  Map<String, String> headers,
  required Map<String, String> form,
});

/// 评分源最小接口（[HeroRatingsService] 实现；测试可注入假实现）。
abstract class HeroRatingsSource {
  /// 取该条目的全部徽章（含种子分）；无数据返回空列表。
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query);

  /// 渐进视图（698 N7-F）：种子/缓存首帧先出，网络源落地逐帧补位。
  /// 默认实现整批一次（假源无需感知）。
  Stream<List<HeroRatingBadge>> watch(HeroRatingQuery query) async* {
    yield await fetch(query);
  }
}

/// Trakt 评分查询桥（由 TraktClient 适配；未登录/未命中返回 null）。
typedef TraktRatingLookup = Future<double?> Function({
  String? imdbId,
  String? tmdbId,
  required bool isMovie,
});

/// 豆瓣反爬挑战未过（挖不出/仍被拦，698 N5-C）——源失败不缓存可重试，
/// 自检按钮据此如实报「反爬拦截」。
class DoubanChallengeException implements Exception {
  const DoubanChallengeException();

  @override
  String toString() => 'DoubanChallengeException';
}

/// 自检结果（设置页「测试评分数据源」用；透出 key 错误文案）。
class HeroRatingsSelfCheck {
  const HeroRatingsSelfCheck({
    this.omdbBadges = const [],
    this.omdbError,
    this.bridgeBadges = const [],
    this.bridgeError,
    this.doubanBlocked = false,
  });

  final List<HeroRatingBadge> omdbBadges;
  final String? omdbError;
  final List<HeroRatingBadge> bridgeBadges;
  final String? bridgeError;

  /// 豆瓣被反爬挑战拦截（挑战未过，698 N5-C）——评分抓取仍会自动重试。
  final bool doubanBlocked;
}

/// 多平台评分拼盘服务（698）：一次查询聚合各源徽章。
///
/// 数据源（缺哪枚隐藏哪枚，绝无空徽章）：
/// - **OMDb**（按 IMDb id）→ IMDb + 烂番茄影评 + Metacritic 三枚；
///   key 未配置时使用**内置免费 key**（698 N3），可被 `omdbApiKey` 覆盖；
/// - **Trakt**（`traktRating` 桥，连账号即亮）→ Trakt 一枚；
/// - **豆瓣爬页**（subject 页 / 搜索兜底，免 key）→ 豆瓣一枚
///   （已有服务端刮削种子分时不再爬，省流量）；
/// - **Letterboxd 爬页**（`/imdb/{tt}/`、`/tmdb/{id}/` 302→film 页，免 key）
///   → Letterboxd 一枚；
/// - 种子徽章（TMDB/🍅/豆瓣，见 [HeroRatingQuery.seedBadges]）本地即得、
///   平台去重时优先（服务端刮削 > 爬页补分）。
///
/// 预留（数据源待接入，接入即亮）：烂番茄观众（🍿）。
///
/// 可靠性（698 修复）：
/// - **按源缓存**：某源失败不缓存该源（下次 fetch 自动重试），成功源缓存
///   不重复打；
/// - **串行队列**：全部 HTTP 请求服务内排队（带抖动），防免费 key 并发
///   限速与爬站请求过密；
/// - 爬页失败静默（返回空成功），绝不影响其他徽章。
class HeroRatingsService implements HeroRatingsSource {
  HeroRatingsService({
    this.omdbApiKey = '',
    this.traktRating,
    RatingsHttpGet? httpGet,
    RatingsHttpPost? httpPost,
    RatingsCacheStore? cacheStore,
    this.queueGap = Duration.zero,
  })  : _httpGet = httpGet ?? _dioGet,
        _httpPost = httpPost ?? _dioPost,
        _cacheStore = cacheStore ?? MemoryRatingsCacheStore();

  /// 内置 OMDb 免费 key（698 N3）：零配置即亮 IMDb/烂番茄/Metacritic 三枚。
  /// 用户配置的 `omdbApiKey` 非空时覆盖；被限流/吊销时换自己的 key。
  static const String builtInOmdbKey = 'bed542e5';

  /// 豆瓣 API 内置 key（698 N14，用户拍板硬编码——同 OMDb 内置 key 先例）：
  /// - [builtInDoubanAppKey]：`api.douban.com` v2 POST（豆瓣 App 抓包 key，
  ///   形态见 feizhaojun.com/?p=3813——POST 只验 apikey）；subject/imdb/
  ///   search 三路直查评分，免反爬、毫秒级；
  /// - [builtInFrodoKey]：`frodo.douban.com` 微信小程序「豆瓣评分」key
  ///   （用户提供），须带 [frodoHeaders] 微信头（缺头报 997）。
  static const String builtInDoubanAppKey = '0ab215a8b1977939201640fa14c66bab';
  static const String builtInFrodoKey = '0ac44ae016490db2204ce0a042db2916';

  /// Frodo（微信小程序）必需请求头（698 N14）。
  static const Map<String, String> frodoHeaders = {
    'User-Agent': 'MicroMessenger/',
    'Referer': 'https://servicewechat.com/wx2f9b06c1de1ccfca/91/page-frame.html',
  };

  /// 爬页 UA（豆瓣/Letterboxd 对非浏览器 UA 有风控，伪装浏览器）。
  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 用户 key 为空时回退内置 key。
  String get _omdbKey =>
      omdbApiKey.trim().isEmpty ? builtInOmdbKey : omdbApiKey.trim();

  final String omdbApiKey;
  final TraktRatingLookup? traktRating;

  /// 串行队列相邻请求的最小间隔（生产传 ~150ms；测试传零）。
  final Duration queueGap;

  final RatingsHttpGet _httpGet;
  final RatingsHttpPost _httpPost;
  final RatingsCacheStore _cacheStore;
  final Random _random = Random();

  /// 豆瓣 cookie jar（698 N7-E）：自造 bid 打底，挑战 POST 响应的
  /// Set-Cookie（通行凭证 `dbsawcv1` 等，真机实录）按名覆盖。
  final Map<String, String> _doubanCookies = {};

  /// 豆瓣反爬挑战宿主（698 N7-E 真机实录）：subject/search 都先 302 到
  /// `sec.douban.com/c` 下发挑战页，表单 `action="/c"` 必须落**该宿主**——
  /// POST 到 movie 域会被当成未解决挑战循环，永不发通行 cookie（旧 bug）。
  static const String doubanChallengeOrigin = 'https://sec.douban.com';

  /// 浏览器 bid cookie（豆瓣风控基线，随请求持久携带）。
  late final String _bidCookie =
      'bid=${List.generate(11, (_) => _bidAlphabet[_random.nextInt(_bidAlphabet.length)]).join()}';
  static const String _bidAlphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// 按源缓存：key = `${源}:${[HeroRatingQuery.cacheKey]}`。
  /// null 结果 = 该源失败（不缓存，下次重试）。
  final Map<String, Future<List<HeroRatingBadge>?>> _cache = {};

  /// 串行队列尾（HTTP 请求依次执行，防限速/爬站过密）。
  Future<void> _queue = Future<void>.value();

  /// 自检标准片：《盗梦空间》（IMDb/烂番茄/Metacritic 三源齐备；
  /// 豆瓣 subject 3541415、Letterboxd inception——film-bridge README 同款）。
  static const String selfCheckImdbId = 'tt1375666';
  static const String selfCheckDoubanId = '3541415';

  Future<T> _serialize<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// HTTP 拉取（698 N7-F 队列分组）：[throttled] 请求过串行队列（带间隔
  /// 抖动）——仅 OMDb 免费 key 需要限速；爬页源（豆瓣/Letterboxd）并行跑
  /// （评分行渐进呈现，不再全串行陪等最慢源）。
  Future<String> _get(
    Uri url, {
    Map<String, String> headers = const {},
    bool throttled = true,
  }) {
    if (!throttled) return _httpGet(url, headers: headers);
    return _serialize(() async {
      if (queueGap > Duration.zero) {
        await Future<void>.delayed(
          queueGap + Duration(milliseconds: _random.nextInt(120)),
        );
      }
      return _httpGet(url, headers: headers);
    });
  }

  static Future<String> _dioGet(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ));
    final response = await dio.getUri<String>(
      url,
      options: Options(headers: headers),
    );
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw StateError('ratings http $code');
    }
    return response.data ?? '';
  }

  /// 豆瓣挑战 POST（698 N5-C）：表单提交 `/c`，**不跟随重定向**——302
  /// 响应头里的 `Set-Cookie` 就是通行凭证，跟随后中间响应头会被丢弃。
  static Future<RatingsHttpPostResult> _dioPost(
    Uri url, {
    Map<String, String> headers = const {},
    required Map<String, String> form,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: false,
      validateStatus: (_) => true,
    ));
    final body = form.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final response = await dio.postUri<String>(
      url,
      data: body,
      options: Options(
        headers: headers,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final cookies = response.headers['set-cookie'];
    return RatingsHttpPostResult(
      body: response.data ?? '',
      setCookie: (cookies == null || cookies.isEmpty) ? null : cookies.join('\n'),
    );
  }

  /// 取该条目的全部徽章：种子分 + 各远端源（按源缓存）。
  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async {
    final seed = query.seedBadges;
    final key = query.cacheKey;
    if (key == null) return seed;
    final results = await Future.wait([
      _cached('omdb', key, () => _fetchOmdb(query)),
      _cached('trakt', key, () => _fetchTrakt(query)),
      _cached('douban', key, () => _fetchDouban(query)),
      _cached('letterboxd', key, () => _fetchLetterboxd(query)),
    ]);
    return [...seed, for (final r in results) ...r];
  }

  /// 渐进视图（698 N7-F）：首帧 = 种子 + 会话缓存即时部分（零网络），
  /// 随后每源落地补位一帧——评分行不再等最慢源（豆瓣挑战流）全齐才显示。
  @override
  Stream<List<HeroRatingBadge>> watch(HeroRatingQuery query) async* {
    const order = ['omdb', 'trakt', 'douban', 'letterboxd'];
    final seed = query.seedBadges;
    final key = query.cacheKey;
    if (key == null) {
      yield seed;
      return;
    }
    final done = <String, List<HeroRatingBadge>>{};
    List<HeroRatingBadge> merged() =>
        [...seed, for (final s in order) ...?done[s]];

    // 先取「此前已完成」的会话缓存（不得把本次新起的 future 当缓存——
    // 否则首帧又变等全齐）。
    final prior = {for (final s in order) s: _cache['$s:$key']};
    final futures = <String, Future<List<HeroRatingBadge>>>{
      'omdb': _cached('omdb', key, () => _fetchOmdb(query)),
      'trakt': _cached('trakt', key, () => _fetchTrakt(query)),
      'douban': _cached('douban', key, () => _fetchDouban(query)),
      'letterboxd': _cached('letterboxd', key, () => _fetchLetterboxd(query)),
    };
    for (final s in order) {
      final f = prior[s];
      if (f != null) {
        final r = await f;
        if (r != null) done[s] = r;
      }
    }
    yield merged();
    for (final s in order) {
      done[s] = await futures[s]!;
      yield merged();
    }
  }

  /// 有分缓存 TTL（698 N7-I）：评分漂移慢，7 天重查一次。
  static const Duration ratingsTtlWithData = Duration(days: 7);

  /// 「确认无数据」空结果 TTL：24h 后自动重查（防永久钉死）。
  static const Duration ratingsTtlEmpty = Duration(hours: 24);

  bool _fresh(RatingsCacheEntry e) =>
      DateTime.now().difference(e.at) <
      (e.hasData ? ratingsTtlWithData : ratingsTtlEmpty);

  /// 按源缓存取数（698 N7-I 双层）：会话内 future map + 持久 store（跨
  /// 服务重建/跨启动命中即零网络）。失败（null）**不写任何缓存** → 下次
  /// 重试；成功（含「确认无数据」空）按 TTL 缓存。
  Future<List<HeroRatingBadge>> _cached(
    String source,
    String key,
    Future<List<HeroRatingBadge>?> Function() run,
  ) async {
    final cacheKey = '$source:$key';
    var future = _cache[cacheKey];
    if (future == null) {
      future = () async {
        final entry = await _cacheStore.read(cacheKey);
        if (entry != null && _fresh(entry)) return entry.badges;
        final result = await run();
        if (result == null) return null;
        await _cacheStore.write(
          cacheKey,
          RatingsCacheEntry(
            badges: result,
            at: DateTime.now(),
            hasData: result.isNotEmpty,
          ),
        );
        return result;
      }();
      _cache[cacheKey] = future;
    }
    final result = await future;
    if (result == null) {
      _cache.remove(cacheKey);
      return const [];
    }
    return result;
  }

  /// OMDb 一枚 key 拿三枚：IMDb + 烂番茄影评 + Metacritic。
  /// 网络/解析异常 → null（失败）；`Response: False` → 空。
  Future<List<HeroRatingBadge>?> _fetchOmdb(HeroRatingQuery query) async {
    final imdbId = query.imdbId?.trim();
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final body = await _get(
        Uri.parse('https://www.omdbapi.com/?apikey=$_omdbKey&i=$imdbId'),
      );
      return parseOmdb(body);
    } catch (_) {
      return null;
    }
  }

  /// Trakt 评分（0–10 → 百分比）。
  Future<List<HeroRatingBadge>?> _fetchTrakt(HeroRatingQuery query) async {
    final lookup = traktRating;
    if (lookup == null) return const [];
    try {
      final rating = await lookup(
        imdbId: query.imdbId,
        tmdbId: query.tmdbId,
        isMovie: query.isMovie,
      );
      if (rating == null || rating <= 0) return const [];
      return [
        HeroRatingBadge(
          RatingPlatform.trakt,
          formatRatingScore(RatingPlatform.trakt, rating * 10),
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 豆瓣评分（698 N14）：**API 优先**（api.douban.com v2 POST 三路直查，
  /// 免反爬毫秒级）；API 不可用/无分时回落旧反爬爬页流（PoW 挑战）。
  Future<List<HeroRatingBadge>?> _fetchDouban(HeroRatingQuery query) async {
    if (query.doubanScore != null && query.doubanScore! > 0) return const [];
    try {
      final rating = await _fetchDoubanApi(query);
      if (_validDouban(rating)) return [_doubanBadge(rating!)];
    } catch (_) {
      // API 网络失败 → 回落爬页流。
    }
    return _fetchDoubanCrawl(query);
  }

  static HeroRatingBadge _doubanBadge(double rating) => HeroRatingBadge(
        RatingPlatform.douban,
        formatRatingScore(RatingPlatform.douban, rating),
      );

  static bool _validDouban(double? v) => v != null && v > 0 && v <= 10;

  /// 豆瓣 API 直查（698 N14，真机验证 rating 9.4 ✓）：
  /// `POST api.douban.com/v2/movie/subject/{id}` → `.../imdb/{tt}` →
  /// `.../movie/search`（标题搜索，film-bridge 相似度匹配宁缺勿错）→
  /// Frodo 搜索兜底（微信小程序接口）。返回 null = 确认无匹配/无分；
  /// 网络失败抛错（由调用方回落爬页）。
  Future<double?> _fetchDoubanApi(HeroRatingQuery query) async {
    final subjectId = query.doubanId?.trim();
    if (subjectId != null && subjectId.isNotEmpty) {
      final rating = _doubanRatingOf(
          await _doubanV2Post('/v2/movie/subject/$subjectId', const {}));
      if (_validDouban(rating)) return rating;
    }
    final imdbId = query.imdbId?.trim();
    if (imdbId != null && imdbId.isNotEmpty) {
      final rating = _doubanRatingOf(
          await _doubanV2Post('/v2/movie/imdb/$imdbId', const {}));
      if (_validDouban(rating)) return rating;
    }
    final title = query.title?.trim();
    if (title != null && title.isNotEmpty) {
      final rating = await _doubanApiSearch(title, query.year);
      if (_validDouban(rating)) return rating;
    }
    return null;
  }

  /// API 搜索匹配（698 N14）：v2 `movie/search` 候选 + Frodo 搜索兜底，
  /// 与爬页搜索同规则（标题相似度 + 年份加权 + 0.6 宁缺勿错）。
  Future<double?> _doubanApiSearch(String title, String? year) async {
    final json = await _doubanV2Post('/v2/movie/search', {
      'q': title,
      'count': '10',
    });
    final best = _bestDoubanMatch(
      title,
      year,
      [
        for (final s in (json['subjects'] as List? ?? const []))
          if (s is Map)
            {
              'title': '${s['title'] ?? ''}',
              'year': '${s['year'] ?? ''}',
              'rating': _doubanRatingOf(s),
            },
      ],
    );
    if (best != null) return best;
    // Frodo 兜底（微信小程序接口，key/头不同源）。
    return _frodoSearch(title, year);
  }

  /// 候选里挑最佳（相似度 ≥ 0.6 才认，宁缺勿错）；返回其评分。
  double? _bestDoubanMatch(
    String title,
    String? year,
    List<Map<String, Object?>> candidates,
  ) {
    var bestScore = 0.0;
    double? bestRating;
    for (final c in candidates) {
      var score = BridgeParsers.titleSimilarity(title, '${c['title'] ?? ''}');
      final y = BridgeParsers.parseYear(year);
      final cy = BridgeParsers.parseYear('${c['year']}');
      if (y != null && cy == y) score += 0.15;
      if (score > bestScore) {
        bestScore = score;
        bestRating = (c['rating'] as double?) ?? _doubanRatingOf(c);
      }
    }
    return bestScore >= 0.6 && _validDouban(bestRating) ? bestRating : null;
  }

  /// Frodo 搜索（698 N14）：`frodo.douban.com/api/v2/search/movie` +
  /// 微信小程序头（缺头报 997）；候选 `items[].target.{title,year,rating}`。
  Future<double?> _frodoSearch(String title, String? year) async {
    final body = await _get(
      Uri.parse(
        'https://frodo.douban.com/api/v2/search/movie'
        '?q=${Uri.encodeComponent(title)}&count=10&apiKey=$builtInFrodoKey',
      ),
      headers: frodoHeaders,
      throttled: false,
    );
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final items = json['items'];
    if (items is! List) return null;
    return _bestDoubanMatch(title, year, [
      for (final it in items)
        if (it is Map && it['target'] is Map)
          {
            'title': '${(it['target'] as Map)['title'] ?? ''}',
            'year': '${(it['target'] as Map)['year'] ?? ''}',
            'rating': _doubanRatingOf(it['target']),
          },
    ]);
  }

  /// 评分抽取：`rating.average`（v2）或 `rating.value`（Frodo），数字/字符串兼容。
  static double? _doubanRatingOf(Object? json) {
    if (json is! Map) return null;
    final rating = json['rating'];
    final raw = rating is Map ? (rating['average'] ?? rating['value']) : null;
    return double.tryParse('${raw ?? ''}');
  }

  /// v2 POST（698 N14）：`api.douban.com` 表单 POST（body: apikey=…），
  /// 文章验证形态（feizhaojun.com/?p=3813：POST 只验 apikey）。
  Future<Map<String, dynamic>> _doubanV2Post(
    String path,
    Map<String, String> params,
  ) async {
    final result = await _httpPost(
      Uri.parse('https://api.douban.com$path'),
      headers: const {
        'User-Agent': 'api-client/1 com.douban.frodo/7.22.0(231)',
      },
      form: {'apikey': builtInDoubanAppKey, ...params},
    );
    final body = result.body.trim();
    if (body.isEmpty) throw StateError('douban api empty');
    final json = jsonDecode(body);
    if (json is! Map) throw StateError('douban api bad body');
    return Map<String, dynamic>.from(json);
  }

  /// 豆瓣爬页兜底（旧反爬挑战流，698 N5-C/N7-E）：API 不可用时保底。
  Future<List<HeroRatingBadge>?> _fetchDoubanCrawl(HeroRatingQuery query) async {
    try {
      String? subjectId = query.doubanId?.trim();
      subjectId = (subjectId == null || subjectId.isEmpty) ? null : subjectId;
      final title = query.title?.trim();

      if (subjectId == null && title != null && title.isNotEmpty) {
        subjectId = await _searchDouban(query);
      }
      if (subjectId == null) return const [];

      final html = await _doubanGet(
        Uri.parse('https://movie.douban.com/subject/$subjectId/'),
      );
      final rating = BridgeParsers.extractRating(html);
      if (rating == null || rating <= 0 || rating > 10) return const [];
      return [_doubanBadge(rating)];
    } catch (_) {
      return null;
    }
  }

  // ── 豆瓣反爬挑战流（698 N5-C）──────────────────────────────────────
  //
  // 豆瓣对非常规客户端返回「点我继续浏览」挑战页（假 200）：SHA-512 工作量
  // 证明（`sha512(cha+nonce)` 前 4 位十六进制为 0）挖到 nonce 后 POST /c
  // 换通行 cookie，浏览器 JS 同款逻辑程序化复刻。

  /// 豆瓣请求头（698 N5-C/N7-E）：完整浏览器头组 + Referer + Cookie jar。
  /// 光加 UA 过不去风控（实测 Referer+Cookie 全套仍 0 命中才挖挑战）。
  Map<String, String> _doubanHeaders() => {
        ..._browserHeaders,
        'Referer': 'https://movie.douban.com/',
        'Cookie': _cookieHeader(),
      };

  /// Cookie 头：自造 bid 打底，服务端下发（挑战 POST 的通行凭证）按名覆盖。
  String _cookieHeader() {
    final jar = {'bid': _bidCookie, ..._doubanCookies};
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 吸收 `Set-Cookie` 的 name=value 段（属性 Path/Expires 等不回传）。
  void _absorbCookies(String raw) {
    for (final part in raw.split('\n')) {
      final nv = part.split(';').first.trim();
      final eq = nv.indexOf('=');
      if (eq <= 0) continue;
      _doubanCookies[nv.substring(0, eq)] = nv.substring(eq + 1);
    }
  }

  /// 豆瓣 GET（698 N5-C/N7-E）：命中挑战页 → 挖矿解决 → 重试；仍被拦换
  /// 宿主策略再解一轮（防挑战宿主变化）；挖不出/仍被拦 → 抛
  /// [DoubanChallengeException]（源失败不缓存，下次自动重试）。
  Future<String> _doubanGet(Uri url) async {
    var html = await _get(url, headers: _doubanHeaders(), throttled: false);
    if (!BridgeParsers.isDoubanChallenge(html)) return html;
    await _solveDoubanChallenge(html, requestUrl: url, useRequestHost: false);
    html = await _get(url, headers: _doubanHeaders(), throttled: false);
    if (BridgeParsers.isDoubanChallenge(html)) {
      await _solveDoubanChallenge(html, requestUrl: url, useRequestHost: true);
      html = await _get(url, headers: _doubanHeaders(), throttled: false);
    }
    if (BridgeParsers.isDoubanChallenge(html)) {
      throw const DoubanChallengeException();
    }
    return html;
  }

  /// 解决一次挑战：解析表单 → 挖 nonce（isolate，防卡 UI）→ POST → 吸收
  /// Set-Cookie 通行凭证（真机实录为 `dbsawcv1`，随名变化自适应）。
  ///
  /// POST 目标 = 表单 action 解析：相对路径**按挑战宿主**落
  /// [doubanChallengeOrigin]（挑战页由 `sec.douban.com/c` 302 下发，
  /// `action="/c"` 必须落该宿主——POST 到 movie 域 = 未解决挑战循环，
  /// 698 N7-E 真机实录旧 bug）；[useRequestHost] 为宿主变化兜底。
  Future<void> _solveDoubanChallenge(
    String html, {
    required Uri requestUrl,
    required bool useRequestHost,
  }) async {
    final form = BridgeParsers.parseDoubanChallenge(html);
    final cha = form?['cha'];
    if (form == null || cha == null || cha.isEmpty) {
      throw const DoubanChallengeException();
    }
    // 挖矿纯 CPU（难度 4 平均 ~6.5 万次 sha512）→ isolate 防卡 UI。
    final nonce = await Isolate.run(() => BridgeParsers.mineDoubanNonce(cha));
    if (nonce == null) throw const DoubanChallengeException();
    final action = form['action'] ?? '/c';
    final Uri target;
    if (action.startsWith('http')) {
      target = Uri.parse(action);
    } else {
      target = Uri.parse(
        '${useRequestHost ? requestUrl.origin : doubanChallengeOrigin}$action',
      );
    }
    final result = await _httpPost(
      target,
      headers: _doubanHeaders(),
      form: {
        'tok': form['tok']!,
        'cha': cha,
        'sol': nonce,
        'red': form['red']!,
        'btnsubmit': '继续浏览',
      },
    );
    final setCookie = result.setCookie;
    if (setCookie == null || setCookie.isEmpty) {
      throw const DoubanChallengeException();
    }
    _absorbCookies(setCookie);
  }

  /// 豆瓣搜索兜底：`subject_search` 候选 + film-bridge 相似度匹配（698 ②）。
  Future<String?> _searchDouban(HeroRatingQuery query) async {
    final title = query.title?.trim();
    if (title == null || title.isEmpty) return null;
    final year = BridgeParsers.parseYear(query.year);
    final searchUrl = Uri.parse(
      'https://search.douban.com/movie/subject_search'
      '?search_text=${Uri.encodeComponent(title)}&cat=1002',
    );
    final html = await _doubanGet(searchUrl);
    final candidates = BridgeParsers.extractDoubanSubjects(html);
    if (candidates.isEmpty) {
      // 698 N7-E：过闸后仍零结构化内容 = 反爬空壳 → 抛错（源失败**不缓存**，
      // 下次自动重试）；有结果页痕迹的空 = 真无匹配 → null（缓存空）。
      final looksReal = html.contains('__DATA__') ||
          html.contains('/subject/') ||
          html.contains('没有找到');
      if (!looksReal) throw const DoubanChallengeException();
      return null;
    }
    String? bestId;
    var bestScore = 0.0;
    for (final c in candidates) {
      var score = BridgeParsers.titleSimilarity(title, c['title'] ?? '');
      // 年份一致小幅加权（标题相似但年份不同的重名条目防误配）。
      final cYear = BridgeParsers.parseYear(c['title']);
      if (year != null && cYear == year) score += 0.15;
      if (score > bestScore) {
        bestScore = score;
        bestId = c['id'];
      }
    }
    // 阈值 0.6：宁缺勿错（匹配不确定就不上徽章）。
    return bestScore >= 0.6 ? bestId : null;
  }

  /// Letterboxd 爬页（免 key）：`/imdb/{tt}/` 或 `/tmdb/{id}/` 302 → film 页，
  /// JSON-LD 抽评分（0–5 → ×2 得 0–10）。
  Future<List<HeroRatingBadge>?> _fetchLetterboxd(HeroRatingQuery query) async {
    try {
      final imdbId = query.imdbId?.trim();
      final tmdbId = query.tmdbId?.trim();
      final Uri route;
      if (imdbId != null && imdbId.isNotEmpty) {
        route = Uri.parse('https://letterboxd.com/imdb/$imdbId/');
      } else if (tmdbId != null && tmdbId.isNotEmpty) {
        route = Uri.parse('https://letterboxd.com/tmdb/$tmdbId/');
      } else {
        return const [];
      }
      final html = await _get(route, headers: _browserHeaders, throttled: false);
      final rating = BridgeParsers.extractRating(html);
      if (rating == null || rating <= 0) return const [];
      // Letterboxd 5 分制 → 0–10。
      final scaled = rating > 5 ? rating : rating * 2;
      if (scaled > 10) return const [];
      return [
        HeroRatingBadge(
          RatingPlatform.letterboxd,
          formatRatingScore(RatingPlatform.letterboxd, scaled),
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 自检（设置页「测试评分数据源」）：标准片实打一次网络，**不读缓存**。
  ///
  /// 三源齐备的标准片查不出 → 解析/响应形态问题；查得出而条目上没有 →
  /// 该条目数据稀疏（正常）。key 错误文案透出到 [HeroRatingsSelfCheck]。
  Future<HeroRatingsSelfCheck> selfCheck() async {
    String? omdbError;
    List<HeroRatingBadge> omdbBadges = const [];
    try {
      final body = await _get(Uri.parse(
        'https://www.omdbapi.com/?apikey=$_omdbKey&i=$selfCheckImdbId',
      ));
      final json = jsonDecode(body);
      if (json is Map && json['Response'] == 'False') {
        omdbError = '${json['Error'] ?? 'OMDb 拒绝请求'}';
      } else {
        omdbBadges = parseOmdb(body);
      }
    } catch (_) {
      omdbError = '网络错误';
    }

    String? bridgeError;
    List<HeroRatingBadge> bridgeBadges = const [];
    var doubanBlocked = false;
    try {
      final badges = <HeroRatingBadge>[];
      // 豆瓣标准片（698 N14）：API 优先（subject/imdb 直查，免反爬）；
      // API 不可用/无分回落爬页（挑战流），仍被拦如实标记。
      double? doubanRating;
      try {
        doubanRating = await _fetchDoubanApi(const HeroRatingQuery(
          doubanId: selfCheckDoubanId,
          imdbId: selfCheckImdbId,
          title: '盗梦空间',
          year: '2010',
        ));
      } catch (_) {
        doubanRating = null;
      }
      if (_validDouban(doubanRating)) {
        badges.add(_doubanBadge(doubanRating!));
      } else {
        try {
          final doubanHtml = await _doubanGet(
            Uri.parse('https://movie.douban.com/subject/$selfCheckDoubanId/'),
          );
          final crawlRating = BridgeParsers.extractRating(doubanHtml);
          if (crawlRating != null && crawlRating > 0) {
            badges.add(_doubanBadge(crawlRating));
          }
        } on DoubanChallengeException {
          doubanBlocked = true;
        }
      }
      // Letterboxd 标准片（/imdb/{tt}/ 路由）。
      final lbHtml = await _get(
        Uri.parse('https://letterboxd.com/imdb/$selfCheckImdbId/'),
        headers: _browserHeaders,
        throttled: false,
      );
      final lbRating = BridgeParsers.extractRating(lbHtml);
      if (lbRating != null && lbRating > 0) {
        final scaled = lbRating > 5 ? lbRating : lbRating * 2;
        badges.add(HeroRatingBadge(
          RatingPlatform.letterboxd,
          formatRatingScore(RatingPlatform.letterboxd, scaled),
        ));
      }
      bridgeBadges = badges;
      if (badges.isEmpty) {
        bridgeError = doubanBlocked
            ? '豆瓣反爬拦截（挑战未过），Letterboxd 也未取到'
            : '豆瓣/Letterboxd 均未取到（反爬或站点改版）';
      }
    } catch (_) {
      bridgeError = '爬页网络错误（反爬或站点改版）';
    }

    return HeroRatingsSelfCheck(
      omdbBadges: omdbBadges,
      omdbError: omdbError,
      bridgeBadges: bridgeBadges,
      bridgeError: bridgeError,
      doubanBlocked: doubanBlocked,
    );
  }

  /// 解析 OMDb 响应 → IMDb / 烂番茄影评 / Metacritic 徽章。
  ///
  /// 容错（698）：Source 匹配忽略大小写与首尾空格；MC 兼容 `67/100`/`67`，
  /// RT 兼容 `69%`/`69`。
  @visibleForTesting
  static List<HeroRatingBadge> parseOmdb(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return const [];
    if (json['Response'] == 'False') return const [];
    final out = <HeroRatingBadge>[];
    final imdb = double.tryParse('${json['imdbRating'] ?? ''}');
    if (imdb != null && imdb > 0) {
      out.add(HeroRatingBadge(
        RatingPlatform.imdb,
        formatRatingScore(RatingPlatform.imdb, imdb),
      ));
    }
    final ratings = json['Ratings'];
    if (ratings is List) {
      for (final row in ratings) {
        if (row is! Map) continue;
        final source = '${row['Source'] ?? ''}'.trim().toLowerCase();
        final value = '${row['Value'] ?? ''}'.trim();
        if (source == 'rotten tomatoes') {
          final v = _parseScoreText(value);
          if (v != null && v > 0) {
            out.add(HeroRatingBadge(
              RatingPlatform.rottenTomatoesCritic,
              formatRatingScore(RatingPlatform.rottenTomatoesCritic, v),
            ));
          }
        } else if (source == 'metacritic') {
          final v = _parseScoreText(value);
          if (v != null && v > 0) {
            out.add(HeroRatingBadge(
              RatingPlatform.metacritic,
              formatRatingScore(RatingPlatform.metacritic, v),
            ));
          }
        }
      }
    }
    return out;
  }

  /// 分数文本 → 数值：`67/100`→67、`69%`→69、`67`→67、`N/A`→null。
  static double? _parseScoreText(String raw) {
    final first = raw.split('/').first.trim();
    final stripped = first.endsWith('%')
        ? first.substring(0, first.length - 1).trim()
        : first;
    return double.tryParse(stripped);
  }
}

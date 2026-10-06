import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 详情页背景主色（按海报/背景图 URL 取色，携带 Emby 鉴权头）。
/// 空 URL、超时或解码失败均得到 null。
final posterColorProvider =
    FutureProvider.autoDispose.family<Color?, String>((ref, url) async {
  if (url.isEmpty) return null;
  final config = ref.watch(embyConfigProvider);
  final token = config?.accessToken;
  final headers = <String, String>{
    if (token != null && token.isNotEmpty) 'X-Emby-Token': token,
  };
  return PosterPalette.extract(url, headers: headers);
});

/// 详情页背景亮色主色（[PosterPalette.extractBright] 派生，与
/// [posterColorProvider] 共享底层缓存，同图只解码一次）。
final posterBrightColorProvider =
    FutureProvider.autoDispose.family<Color?, String>((ref, url) async {
  if (url.isEmpty) return null;
  final config = ref.watch(embyConfigProvider);
  final token = config?.accessToken;
  final headers = <String, String>{
    if (token != null && token.isNotEmpty) 'X-Emby-Token': token,
  };
  return PosterPalette.extractBright(url, headers: headers);
});

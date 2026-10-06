import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 详情页背景三色组（原始主色 top-3，频次降序，见 [PosterPalette.compute]；
/// 按海报/背景图 URL 取色，携带 Emby 鉴权头）。
/// 空 URL、超时或解码失败均得到 null。
final posterTrioProvider =
    FutureProvider.autoDispose.family<List<Color>?, String>((ref, url) async {
  if (url.isEmpty) return null;
  final config = ref.watch(embyConfigProvider);
  final token = config?.accessToken;
  final headers = <String, String>{
    if (token != null && token.isNotEmpty) 'X-Emby-Token': token,
  };
  return PosterPalette.extractTrio(url, headers: headers);
});

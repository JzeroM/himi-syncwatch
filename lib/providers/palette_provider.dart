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

/// 698 N43：首页 hero 当前主海报首色（extract 首色）——全页面背景
/// 跟随海报色调（698 N46：背景色场走海报底部三带取色）。
/// 首页 hero 切换时写入；null = 未就绪（背景回退中性）。
final heroToneProvider = StateProvider<Color?>((ref) => null);

/// 698 N44：首页 hero 当前海报 URL——全屏氛围洗背景图源（同源零分割）。
/// 首页轮播切换时写入；null = 未就绪（背景回退织物微渐变）。
final heroPosterUrlProvider = StateProvider<String?>((ref) => null);

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_backdrop.dart';

/// 测试用图片 provider（可控就绪时机——保持旧场守卫）。
class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  _FakeImageProvider(this.image, {this.completer});

  final ui.Image image;

  /// 慢就绪：非 null 时须手动 complete 才出帧。
  final Completer<ImageInfo>? completer;

  @override
  Future<_FakeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      _FakeImageProvider key, ImageDecoderCallback decode) {
    if (completer != null) {
      return OneFrameImageStreamCompleter(completer!.future);
    }
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}

Future<ui.Image> _posterImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 16, 24), Paint()..color = const Color(0xFFCC4422));
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 24);
  picture.dispose();
  return image;
}

Widget _app({required bool isDark}) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: PosterBackdrop(base: Color(0xFFF4F5F7))),
      ),
    );

Future<void> _setUrl(WidgetTester tester, String url) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
  container.read(heroPosterUrlProvider.notifier).state = url;
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

void main() {
  final fake = <String, _FakeImageProvider>{};

  setUp(() {
    PosterPalette.debugReset();
    fake.clear();
  });
  tearDown(PosterPalette.debugReset);

  testWidgets('回退态（无海报 URL）：纯平色基底（TV 拍板不变）', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    expect(find.byType(ImageFiltered), findsNothing);
    final box = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .first
        .decoration! as BoxDecoration;
    expect(box.color, isNotNull, reason: '回退平色');
    expect(box.gradient, isNull);
  });

  testWidgets('N51 模糊氛围场：降采样 + blur + 梯度压暗层', (tester) async {
    final image = await _posterImage();
    debugAmbientImageProvider = (url) =>
        fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://a/p.jpg');

    // 降采样氛围场：ResizeImage（宽 24）+ blur + ColorFiltered。
    expect(find.byType(ImageFiltered), findsWidgets, reason: '轻 blur 抹细节');
    expect(find.byType(ColorFiltered), findsWidgets, reason: '降饱和 ×0.85');
    final img = tester.widget<Image>(find.byType(Image).first);
    expect(img.image, isA<ResizeImage>(), reason: '降采样解码（宽 24 抹细节）');
    final resize = img.image as ResizeImage;
    expect(resize.width, 24, reason: '解码级局部像素加权平均');

    // 梯度压暗层（顶部受光 → 底部沉暗）。
    final gradients = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .toList();
    expect(gradients, isNotEmpty, reason: '梯度压暗层在');
    final g = gradients.first;
    expect(g.colors.first.computeLuminance(),
        greaterThan(g.colors.last.computeLuminance()),
        reason: '顶部受光亮于底部（明暗流动 + 白字可读）');
    debugAmbientImageProvider = null;
  });

  testWidgets('N51 保持旧场：新图就绪前不换场', (tester) async {
    final image = await _posterImage();
    debugAmbientImageProvider = (url) =>
        fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://old/p.jpg');
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    // 新 URL 慢就绪（手动 complete）——未就绪期间保持旧场。
    final slow = Completer<ImageInfo>();
    fake['https://new/p.jpg'] = _FakeImageProvider(image, completer: slow);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
    container.read(heroPosterUrlProvider.notifier).state = 'https://new/p.jpg';
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    final sw = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(sw.child, isNotNull, reason: '保持旧场（不闪空白）');

    // 就绪后切换完成（drain）。
    slow.complete(ImageInfo(image: image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    debugAmbientImageProvider = null;
  });

  test('预热函数：precacheAmbientPoster 可用', () {
    precacheAmbientPoster('https://warm/p.jpg');
  });
}

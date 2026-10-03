import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/sync_debug_panel.dart';
import 'package:himi_syncwatch/services/decoder_report.dart';

import '../helpers/test_fakes.dart';

/// 黑屏多档取证的面板行：
/// - 「输出」展示生效视频输出通道（产物身份项，随档位切换）；
/// - 「截帧」触发 mdk snapshot 判读（非黑=合成侧问题）。
void main() {
  Widget buildPanel({
    String videoOutput = 'surfaceView',
    String? snapshotInfo,
    VoidCallback? onSnapshot,
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SyncDebugPanel(
            isHost: true,
            rtmChannel: '',
            rtmStatus: '',
            metadataTestResult: '',
            voStatus: '',
            hdrType: '',
            isSinglePlayer: true,
            playbackState: 'playing',
            mediaStatusStr: 'prepared',
            positionMs: 0,
            durationMs: 0,
            bufferedMs: 0,
            mediaBitrate: 0,
            mediaFormat: '',
            videoCodecName: '',
            videoResolution: '',
            videoFps: 0,
            videoBitrate: 0,
            pixelFormat: '',
            doviProfile: 0,
            audioCodecName: '',
            audioSampleRate: 0,
            audioChannels: 0,
            audioBitrate: 0,
            stereoDownmix: '',
            audioFilter: '',
            textureId: 7,
            textureSize: '1920x1080',
            videoOutput: videoOutput,
            snapshotInfo: snapshotInfo,
            onSnapshot: onSnapshot,
            decodeMode: 'auto',
            actualVideoDecoders: '',
            mdkRawDecoder: '',
            decoderReport: DecoderReport.empty,
            audioBackend: '',
            dvCapability: '',
            buildSummary: '',
            stallSummary: '',
            bufProgress: -1,
            deepLogActive: false,
            onExportStutter: () => '',
            onDrag: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('输出行展示生效视频输出通道', (tester) async {
    await tester.pumpWidget(buildPanel(videoOutput: 'surfaceView'));
    await tester.pump();

    expect(find.text('输出'), findsOneWidget);
    expect(find.text('surfaceView'), findsOneWidget);
    expect(find.text('纹理'), findsOneWidget);
    expect(find.text('7 | 1920x1080'), findsOneWidget);
  });

  testWidgets('档位切换后面板展示新通道（tunnel）', (tester) async {
    await tester.pumpWidget(buildPanel(videoOutput: 'tunnel'));
    await tester.pump();

    expect(find.text('tunnel'), findsOneWidget);
  });

  testWidgets('截帧行展示取帧结果并可触发取证', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(buildPanel(
      snapshotInfo: '409600B · 亮度 12.3%',
      onSnapshot: () => tapped++,
    ));
    await tester.pump();

    expect(find.text('截帧'), findsOneWidget);
    expect(find.text('409600B · 亮度 12.3%'), findsOneWidget);

    final button = find.byKey(const Key('snapshotProbeButton'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('未取帧时提示引导，未传 onSnapshot 时隐藏整行', (tester) async {
    await tester.pumpWidget(buildPanel(onSnapshot: () {}));
    await tester.pump();
    expect(find.text('点击右侧取帧'), findsOneWidget);

    await tester.pumpWidget(buildPanel());
    await tester.pump();
    expect(find.byKey(const Key('snapshotProbeButton')), findsNothing);
    expect(find.text('截帧'), findsNothing);
  });
}

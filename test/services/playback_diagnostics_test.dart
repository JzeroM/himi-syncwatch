import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/playback_diagnostics.dart';

void main() {
  group('PlaybackDiagnostics 采样', () {
    test('首个样本建立会话时间基准', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 5000, state: 'playing', status: 'loaded');
      expect(diag.sampleCount, 1);
      expect(diag.elapsedMs, 0);

      now = now.add(const Duration(milliseconds: 250));
      diag.addSample(
          pos: 250, buffered: 5000, state: 'playing', status: 'loaded');
      expect(diag.elapsedMs, 250);
      expect(diag.sampleCount, 2);
    });

    test('缓冲余量直接取 buffered()，不再减去 position', () {
      // fvp 的 Player.buffered() 返回"播放头前方的已缓冲时长"，
      // 不是缓冲区绝对终点。旧实现误算成 buffered - pos，
      // 在 pos=257s 时会产出 -257000ms 之类无意义的假值。
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 1000, buffered: 4000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(milliseconds: 250));
      diag.addSample(
          pos: 5000, buffered: 4000, state: 'playing', status: 'loaded');

      expect(diag.minAheadMs, 4000);
    });

    test('长时间播放后缓冲余量不会变成巨大负数', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      // 模拟播放 4 分钟、始终维持 1s 缓冲
      for (var i = 0; i < 960; i++) {
        diag.addSample(
            pos: i * 250, buffered: 1000, state: 'playing', status: 'loaded');
        now = now.add(const Duration(milliseconds: 250));
      }

      expect(diag.minAheadMs, 1000);

      // 时间线的缓冲余量列（第 2 列）应恒为 1000，不随 pos 增长。
      // 注意末列无 fps 时会渲染为 '-'，所以不能整体断言不含 '-'。
      final rows = diag.exportTimeline().trim().split('\n').skip(1);
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final cols = row.trim().split(RegExp(r'\s+'));
        expect(cols.length, greaterThanOrEqualTo(4));
        expect(int.tryParse(cols[1]), 1000,
            reason: '缓冲余量列应恒为 1000，实际: "$row"');
      }
    });

    test('负数/未知缓冲值归零处理', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: -1, state: 'playing', status: 'loaded');
      now = now.add(const Duration(milliseconds: 250));
      diag.addSample(
          pos: 250, buffered: 2000, state: 'playing', status: 'loaded');

      expect(diag.minAheadMs, 0);
    });

    test('无采样时最小缓冲余量为 null', () {
      final diag = PlaybackDiagnostics();
      expect(diag.minAheadMs, isNull);
      expect(diag.summary(), contains('最小缓冲余量: -'));
    });

    test('记录最小缓冲余量及其出现时刻', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 3000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 2));
      diag.addSample(
          pos: 2000, buffered: 2100, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 2));
      diag.addSample(
          pos: 4000, buffered: 9000, state: 'playing', status: 'loaded');

      expect(diag.minAheadMs, 2100);
      expect(diag.minAheadAtMs, 2000);
    });

    test('样本数超过上限时丢弃最旧的', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      for (var i = 0; i < PlaybackDiagnostics.maxSamples + 50; i++) {
        diag.addSample(
            pos: i * 250, buffered: 100000, state: 'playing', status: 'loaded');
        now = now.add(const Duration(milliseconds: 250));
      }

      expect(diag.sampleCount, PlaybackDiagnostics.maxSamples);
    });
  });

  group('PlaybackDiagnostics 自动重置', () {
    test('位置回退超过阈值视为 seek，自动重置', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 1000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 1));
      diag.addSample(
          pos: 60000, buffered: 61000, state: 'playing', status: 'loaded');
      expect(diag.sampleCount, 2);

      // 向前拖动进度条：位置大幅回退
      now = now.add(const Duration(seconds: 1));
      diag.addSample(
          pos: 5000, buffered: 6000, state: 'playing', status: 'loaded');

      expect(diag.sampleCount, 1, reason: 'seek 后时间线应只剩新样本');
    });

    test('位置小幅回退（解码抖动）不触发重置', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 10000, buffered: 11000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(milliseconds: 250));
      diag.addSample(
          pos: 9900, buffered: 11000, state: 'playing', status: 'loaded');

      expect(diag.sampleCount, 2, reason: '小于阈值的回退属于正常抖动');
    });

    test('reloading 为真时重置，避免换集数据污染', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 1000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 1));
      diag.addSample(
          pos: 1000,
          buffered: 2000,
          state: 'playing',
          status: 'loading',
          reloading: true);

      expect(diag.sampleCount, 1);
    });
  });

  group('PlaybackDiagnostics 卡顿统计', () {
    test('超过阈值的缓冲中断计入卡顿', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 2000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 5));
      diag.onStallStart('buffering');
      expect(diag.isStalling, isTrue);
      now = now.add(const Duration(milliseconds: 800));
      diag.onStallEnd();

      expect(diag.isStalling, isFalse);
      expect(diag.stallCount, 1);
      expect(diag.stallTotalMs, 800);
      expect(diag.stallMaxMs, 800);
    });

    test('短于阈值的抖动不计入卡顿', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 2000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 1));
      diag.onStallStart('buffering');
      now = now.add(const Duration(milliseconds: 80));
      diag.onStallEnd();

      expect(diag.stallCount, 0,
          reason: '正常 seek / 切轨抖动应被阈值过滤');
    });

    test('重复 start 不会覆盖首次卡顿计时', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 2000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 2));
      diag.onStallStart('buffering');
      now = now.add(const Duration(milliseconds: 500));
      diag.onStallStart('underflow');
      now = now.add(const Duration(milliseconds: 500));
      diag.onStallEnd();

      expect(diag.stallCount, 1);
      expect(diag.stallTotalMs, 1000,
          reason: '应从首次进入缓冲开始计时');
    });

    test('未开始计时时调用 end 不产生记录', () {
      final diag = PlaybackDiagnostics();
      diag.onStallEnd();
      expect(diag.stallCount, 0);
    });

    test('reapStaleStall 兜底结算悬挂计时', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 2000, state: 'playing', status: 'loaded');
      now = now.add(const Duration(seconds: 1));
      diag.onStallStart('buffering');

      now = now.add(
          const Duration(milliseconds: PlaybackDiagnostics.stallStaleGuardMs));
      expect(diag.isStalling, isTrue);
      diag.reapStaleStall();

      expect(diag.isStalling, isFalse);
      expect(diag.stallCount, 1);
      expect(diag.stallTotalMs, PlaybackDiagnostics.stallStaleGuardMs);
    });

    test('卡顿事件超上限时丢弃最旧的', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 2000, state: 'playing', status: 'loaded');
      for (var i = 0; i < PlaybackDiagnostics.maxStalls + 20; i++) {
        now = now.add(const Duration(milliseconds: 200));
        diag.onStallStart('buffering');
        now = now.add(const Duration(milliseconds: 400));
        diag.onStallEnd();
      }

      expect(diag.stallCount, PlaybackDiagnostics.maxStalls);
    });
  });

  group('PlaybackDiagnostics 帧率与事件', () {
    test('updateFps 忽略非法值', () {
      final diag = PlaybackDiagnostics();
      diag.updateFps(null);
      expect(diag.latestFps, isNull);
      diag.updateFps(0);
      expect(diag.latestFps, isNull);
      diag.updateFps(-5);
      expect(diag.latestFps, isNull);
      diag.updateFps(23.976);
      expect(diag.latestFps, closeTo(23.976, 0.001));
    });

    test('后续样本带上最新实测帧率', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      diag.addSample(
          pos: 0, buffered: 1000, state: 'playing', status: 'loaded');
      diag.updateFps(23.5);
      now = now.add(const Duration(milliseconds: 250));
      diag.addSample(
          pos: 250, buffered: 1000, state: 'playing', status: 'loaded');

      expect(diag.exportTimeline(), contains('23.5'));
    });

    test('事件原文超上限时丢弃最旧的', () {
      final diag = PlaybackDiagnostics();
      final total = PlaybackDiagnostics.maxEvents + 30;
      for (var i = 0; i < total; i++) {
        diag.addEvent('thread.video', 'detail$i', i);
      }
      final exported = diag.exportEvents();
      // 保留最近 maxEvents 条，即 detail30 ~ detail229
      expect(exported, isNot(contains('detail0 |')));
      expect(exported, contains('detail30 |'));
      expect(exported, contains('detail${total - 1} |'));
    });

    test('reset 清空全部数据', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
          pos: 0, buffered: 1000, state: 'playing', status: 'loaded');
      diag.onStallStart('buffering');
      diag.note('测试');
      diag.addEvent('thread.video', 'x', 1);

      diag.reset();

      expect(diag.sampleCount, 0);
      expect(diag.stallCount, 0);
      expect(diag.isStalling, isFalse);
      expect(diag.notes, isEmpty);
      expect(diag.exportEvents(), contains('无 mdk 事件'));
    });
  });

  group('PlaybackDiagnostics 导出', () {
    test('无样本时导出占位文本', () {
      final diag = PlaybackDiagnostics();
      expect(diag.exportTimeline(), contains('无采样数据'));
      expect(diag.exportStalls(), contains('无卡顿记录'));
    });

    test('时间线降采样到不超过上限，且保留首尾', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      for (var i = 0; i < 2000; i++) {
        diag.addSample(
            pos: i * 250,
            buffered: 4000,
            state: 'playing',
            status: 'loaded');
        now = now.add(const Duration(milliseconds: 250));
      }

      final rows = diag.exportTimeline().trim().split('\n');
      // 1 行表头 + 降采样后的数据行
      expect(rows.length - 1, lessThanOrEqualTo(PlaybackDiagnostics.exportMaxRows));
      // 首尾样本的缓冲余量都是 4000，应同时出现在输出中
      final data = rows.skip(1).toList();
      expect(data.first, contains('4000'));
      expect(data.last, contains('4000'));
    });

    test('样本数未超上限时不降采样', () {
      var now = DateTime(2026, 1, 1);
      final diag = PlaybackDiagnostics(clock: () => now);

      for (var i = 0; i < 50; i++) {
        diag.addSample(
            pos: i * 250, buffered: 9000, state: 'playing', status: 'loaded');
        now = now.add(const Duration(milliseconds: 250));
      }

      final rows = diag.exportTimeline().trim().split('\n');
      expect(rows.length - 1, 50);
    });

    test('summary 覆盖关键指标与深度诊断提示', () {
      final diag = PlaybackDiagnostics();
      final summary = diag.summary();
      expect(summary, contains('卡顿次数'));
      expect(summary, contains('最小缓冲余量'));
      expect(summary, contains('需开启深度诊断'));
    });
  });

  // cache 与缓冲进度是区分「网络喂不进」与「解码跟不上」的两列证据：
  // 卡顿时 cache 归零说明数据侧断供；cache 仍有余量而 fps 塌陷则指向解码。
  group('时间线 缓存与缓冲进度列', () {
    test('表头包含 cache 与 buf 列', () {
      final head = PlaybackDiagnostics().exportTimeline().split('\n').first;
      expect(head, contains('cache(s)'));
      expect(head, contains('buf%'));
      expect(head, contains('ahead(ms)'));
    });

    test('未传新参数时保持未知，现有调用方无需改动', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
          pos: 0, buffered: 4000, state: 'playing', status: 'loaded');

      final sample = diag.exportTimeline();
      expect(sample, contains(' -')); // cache 缺省
      expect(sample, contains('   -')); // buf 缺省
      final cols = sample.trim().split('\n').last.trim().split(RegExp(r'\s+'));
      expect(cols[2], '-', reason: 'cache 列应为占位符');
      expect(cols[3], '-', reason: 'buf 列应为占位符');
    });

    test('记录缓存秒数与缓冲进度', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
        pos: 0,
        buffered: 0,
        state: 'playing',
        status: 'buffering',
        cacheSeconds: 0.0,
        bufProgress: 0,
      );

      final cols = diag
          .exportTimeline()
          .trim()
          .split('\n')
          .last
          .trim()
          .split(RegExp(r'\s+'));
      expect(cols[1], '0', reason: 'ahead');
      expect(double.parse(cols[2]), 0.0, reason: '卡顿时缓存应为 0');
      expect(cols[3], '0%', reason: '缓冲进度应为 0%');
    });

    test('缓存秒数保留一位小数', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
          pos: 0,
          buffered: 4000,
          state: 'playing',
          status: 'loaded',
          cacheSeconds: 1.0);

      final cols = diag
          .exportTimeline()
          .trim()
          .split('\n')
          .last
          .trim()
          .split(RegExp(r'\s+'));
      expect(cols[2], '1.0');
    });

    test('缓冲进度越界仍如实显示，不静默修正', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
          pos: 0,
          buffered: 4000,
          state: 'playing',
          status: 'loaded',
          bufProgress: 100);
      expect(diag.exportTimeline(), contains('100%'));
    });

    test('新建样本不会污染上一次的缓存值', () {
      final diag = PlaybackDiagnostics();
      diag.addSample(
          pos: 0,
          buffered: 4000,
          state: 'playing',
          status: 'loaded',
          cacheSeconds: 3.5,
          bufProgress: 80);
      diag.addSample(
          pos: 250,
          buffered: 4000,
          state: 'playing',
          status: 'loaded',
          cacheSeconds: 0.0,
          bufProgress: 0);

      final rows = diag.exportTimeline().trim().split('\n').skip(1).toList();
      expect(rows.length, 2);
      expect(rows.first, contains('3.5'));
      expect(rows.last, contains('0.0'));
      expect(rows.first, contains('80%'));
      expect(rows.last, contains('0%'));
    });
  });
}

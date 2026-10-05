import 'dart:ffi';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/network_speed_meter.dart';

/// 按序返回的计数器（超出后重复最后一个值）。
class _SeqCounter implements RxCounter {
  _SeqCounter(this.values);

  final List<int?> values;
  int i = 0;

  @override
  Future<int?> readRxBytes() async {
    final v = values[i < values.length ? i : values.length - 1];
    i++;
    return v;
  }
}

const _procNetDevSample = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 57500227100 26069874    0    0    0     0          0         0 57500227100 26069874    0    0    0     0       0          0
enp1s0:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0
wlp2s0: 4998551918 18428917    0    0    0     0          0         0 11218816673 22342447    0    0    0     0       0          0
''';

void main() {
  group('NetworkSpeedMeter.parseRxBytes（/proc/net/dev）', () {
    test('多接口求和并排除回环 lo', () {
      // lo 57500227100 被排除；enp1s0 0 + wlp2s0 4998551918
      expect(NetworkSpeedMeter.parseRxBytes(_procNetDevSample), 4998551918);
    });

    test('仅回环 → 无有效接口返回 null', () {
      const onlyLo = '''
 face |bytes packets
    lo: 12345 1
''';
      expect(NetworkSpeedMeter.parseRxBytes(onlyLo), isNull);
    });

    test('空内容 → null', () {
      expect(NetworkSpeedMeter.parseRxBytes(''), isNull);
    });
  });

  group('NetworkSpeedMeter.formatMBs', () {
    test('十进制 MB 两位小数', () {
      expect(NetworkSpeedMeter.formatMBs(4890000), '4.89 MB/s');
      expect(NetworkSpeedMeter.formatMBs(0), '0.00 MB/s');
      expect(NetworkSpeedMeter.formatMBs(1234567), '1.23 MB/s');
    });
  });

  group('NetworkSpeedMeter 采样（fakeAsync）', () {
    test('首 tick 记基线，次 tick 起输出差分；stop 停表', () {
      fakeAsync((async) {
        final counter = _SeqCounter([1000, 3000, 7000]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        expect(meter.isRunning, isTrue);

        async.elapse(const Duration(seconds: 1)); // 首 tick：基线 1000
        expect(values, isEmpty, reason: '首 tick 仅记基线不输出');

        async.elapse(const Duration(seconds: 1)); // 3000-1000
        expect(values, [2000.0]);

        async.elapse(const Duration(seconds: 1)); // 7000-3000
        expect(values.last, 4000.0);

        meter.stop();
        expect(meter.isRunning, isFalse);
        async.elapse(const Duration(seconds: 3));
        expect(values, hasLength(2), reason: 'stop 后不再采样');
      });
    });

    test('连续 3 次读取失败 → 回吐 null 并停止', () {
      fakeAsync((async) {
        final counter = _SeqCounter([null, null, null, null]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        async.elapse(const Duration(seconds: 1)); // fail 1（无输出）
        expect(values, isEmpty);
        async.elapse(const Duration(seconds: 1)); // fail 2
        async.elapse(const Duration(seconds: 1)); // fail 3 → stop + null
        expect(values, [null]);
        expect(meter.isRunning, isFalse);
      });
    });

    test('计数器重置（负差分）→ 本 tick 报 0', () {
      fakeAsync((async) {
        final counter = _SeqCounter([5000, 1000]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        async.elapse(const Duration(seconds: 1)); // 基线 5000
        async.elapse(const Duration(seconds: 1)); // 1000-5000 → 反跳
        expect(values, [0.0]);
        meter.stop();
      });
    });

    test('间歇失败（<3 次）不打断采样', () {
      fakeAsync((async) {
        final counter = _SeqCounter([1000, null, 6000, 8000]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        async.elapse(const Duration(seconds: 1)); // 基线 1000
        async.elapse(const Duration(seconds: 1)); // null（failures=1，无输出）
        expect(values, isEmpty);
        async.elapse(const Duration(seconds: 1)); // 6000-1000
        expect(values, [5000.0]);
        meter.stop();
      });
    });
  });

  group('AndroidTrafficStatsRxCounter（TrafficStats channel）', () {
    test('channel 正常 → 返回整机累计字节', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(
          AndroidTrafficStatsRxCounter.channel, null));
      messenger.setMockMethodCallHandler(AndroidTrafficStatsRxCounter.channel,
          (call) async {
        expect(call.method, 'totalRxBytes');
        return 4242;
      });
      final c = AndroidTrafficStatsRxCounter(fallback: _SeqCounter([999]));
      expect(await c.readRxBytes(), 4242);
    });

    test('channel 返回 null（UNSUPPORTED）→ 回退 fallback', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(
          AndroidTrafficStatsRxCounter.channel, null));
      messenger.setMockMethodCallHandler(
          AndroidTrafficStatsRxCounter.channel, (call) async => null);
      final c = AndroidTrafficStatsRxCounter(fallback: _SeqCounter([999]));
      expect(await c.readRxBytes(), 999);
    });

    test('channel 异常（MissingPlugin 等）→ 回退 fallback', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(
          AndroidTrafficStatsRxCounter.channel, null));
      messenger.setMockMethodCallHandler(AndroidTrafficStatsRxCounter.channel,
          (call) async => throw PlatformException(code: 'no-engine'));
      final c = AndroidTrafficStatsRxCounter(fallback: _SeqCounter([999]));
      expect(await c.readRxBytes(), 999);
    });
  });

  group('FFI 结构布局回归（x64 ABI）', () {
    test('Windows MibIfRow2：行大小 1352、inOctets @1208', () {
      expect(sizeOf<MibIfRow2>(), 1352);
      final p = calloc<MibIfRow2>();
      try {
        p.ref.inOctets = 0x1122334455667788;
        // 按手算偏移 1208 读回，验证声明布局与 MSVC x64 一致
        final raw = (p.cast<Uint8>() + 1208).cast<Uint64>();
        expect(raw.value, 0x1122334455667788);
      } finally {
        calloc.free(p);
      }
    });

    test('Windows 表头：Table[] 起点 8 字节（NumEntries + padding）', () {
      expect(kMibIfTable2RowsOffset, 8);
      expect(sizeOf<MibIfRow2>() % kMibIfTable2RowsOffset, 0);
    });

    test('Darwin ifaddrs：LP64 布局 56 字节', () {
      expect(sizeOf<DarwinIfaddrs>(), 56);
    });

    test('Darwin if_data：ifiIbytes @32（u32）', () {
      expect(sizeOf<DarwinIfData>() >= 36, isTrue);
      final p = calloc<DarwinIfData>();
      try {
        p.ref.ifiIbytes = 0xAABBCCDD;
        final raw = (p.cast<Uint8>() + 32).cast<Uint32>();
        expect(raw.value, 0xAABBCCDD);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('ProcNetDevRxCounter（路径回退）', () {
    test('首选路径不可读 → 回退次路径读到累计字节', () async {
      final dir = Directory.systemTemp.createTempSync('rx_counter_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final fallback = File('${dir.path}/netdev')
        ..writeAsStringSync(_procNetDevSample);
      final counter = ProcNetDevRxCounter(
        paths: ['${dir.path}/does_not_exist', fallback.path],
      );
      expect(await counter.readRxBytes(), 4998551918);
    });

    test('全部路径失败 → null（顶栏隐藏网速）', () async {
      final dir = Directory.systemTemp.createTempSync('rx_counter_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final counter = ProcNetDevRxCounter(
        paths: ['${dir.path}/a', '${dir.path}/b'],
      );
      expect(await counter.readRxBytes(), isNull);
    });

    test('默认路径含 Android SELinux 回退 /proc/self/net/dev', () {
      expect(
        ProcNetDevRxCounter().paths,
        ['/proc/net/dev', '/proc/self/net/dev'],
      );
    });
  });

  group('createDefaultRxCounter（平台分流）', () {
    test('Android → TrafficStats；Linux → /proc；其余已知平台均有实现', () {
      final counter = createDefaultRxCounter();
      if (Platform.isAndroid) {
        expect(counter, isA<AndroidTrafficStatsRxCounter>());
      } else if (Platform.isLinux) {
        expect(counter, isA<ProcNetDevRxCounter>());
      } else if (Platform.isWindows) {
        expect(counter, isA<WindowsRxCounter>());
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(counter, isA<DarwinRxCounter>());
      } else {
        expect(counter, isNull);
      }
    });
  });
}

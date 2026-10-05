import 'dart:ffi';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/network_speed_meter.dart';

/// 按序返回的计数器（超出后重复最后一个值）。
class _SeqCounter implements RxCounter {
  _SeqCounter(this.values);

  final List<int?> values;
  int i = 0;

  @override
  int? readRxBytes() {
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
    test('基线 + 每秒差分输出字节/秒；stop 停表', () {
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
        expect(values, isEmpty, reason: '首读仅记基线不输出');

        async.elapse(const Duration(seconds: 1));
        expect(values, [2000.0]);

        async.elapse(const Duration(seconds: 1));
        expect(values.last, 4000.0);

        meter.stop();
        expect(meter.isRunning, isFalse);
        async.elapse(const Duration(seconds: 3));
        expect(values, hasLength(2), reason: 'stop 后不再采样');
      });
    });

    test('首读失败 → onSpeed(null) 且不启动', () {
      fakeAsync((async) {
        final counter = _SeqCounter([null]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        expect(values, [null]);
        expect(meter.isRunning, isFalse);
        async.elapse(const Duration(seconds: 5));
        expect(values, [null]);
      });
    });

    test('连续 3 次读取失败 → 回吐 null 并停止', () {
      fakeAsync((async) {
        final counter = _SeqCounter([1000, null, null, null]);
        final values = <double?>[];
        final meter = NetworkSpeedMeter(
          counter: counter,
          onSpeed: values.add,
          interval: const Duration(seconds: 1),
        );
        meter.start();
        async.elapse(const Duration(seconds: 3));
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
        async.elapse(const Duration(seconds: 1));
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
        async.elapse(const Duration(seconds: 1)); // null（failures=1，无输出）
        expect(values, isEmpty);
        async.elapse(const Duration(seconds: 1)); // 6000-1000
        expect(values, [5000.0]);
        meter.stop();
      });
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

  group('createDefaultRxCounter（平台分流）', () {
    test('Linux/Android → /proc/net/dev；其余已知平台均有实现', () {
      final counter = createDefaultRxCounter();
      if (Platform.isLinux || Platform.isAndroid) {
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

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 平台累计接收字节计数器。
///
/// 返回网络栈的累计接收字节（整机口径，播放时 ≈ 视频流下载量）；
/// 平台不支持或读取失败返回 null。
abstract class RxCounter {
  int? readRxBytes();
}

/// Linux/Android：解析 `/proc/net/dev` 累计 rx 字节（排除回环 `lo`）。
///
/// Android 上 `/proc/net/dev` 受 SELinux 限制（EACCES），回退应用可读的
/// `/proc/self/net/dev`（同内容的本进程 netns 视图）；按 [paths] 顺序
/// 逐个尝试，全部失败返回 null。
class ProcNetDevRxCounter implements RxCounter {
  ProcNetDevRxCounter({
    this.paths = const ['/proc/net/dev', '/proc/self/net/dev'],
  });

  final List<String> paths;

  @override
  int? readRxBytes() {
    for (final path in paths) {
      try {
        final parsed =
            NetworkSpeedMeter.parseRxBytes(File(path).readAsStringSync());
        if (parsed != null) return parsed;
      } catch (_) {
        // EACCES/不存在 → 尝试下一路径
      }
    }
    return null;
  }
}

/// Windows：`GetIfTable2` 读网卡表，求和 `InOctets`。
class WindowsRxCounter implements RxCounter {
  WindowsRxCounter();

  late final DynamicLibrary _lib = DynamicLibrary.open('iphlpapi.dll');
  late final int Function(Pointer<Pointer<Uint8>>) _getTable =
      _lib.lookupFunction<Uint32 Function(Pointer<Pointer<Uint8>>),
          int Function(Pointer<Pointer<Uint8>>)>('GetIfTable2');
  late final void Function(Pointer<Void>) _freeTable = _lib.lookupFunction<
      Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
    'FreeMibTable',
  );

  @override
  int? readRxBytes() {
    final out = calloc<Pointer<Uint8>>();
    try {
      if (_getTable(out) != 0) return null;
      final table = out.value;
      if (table == nullptr) return null;
      try {
        final numEntries = table.cast<Uint32>().value;
        final rowSize = sizeOf<MibIfRow2>();
        var sum = 0;
        // MIB_IF_TABLE2 { ULONG NumEntries; MIB_IF_ROW2 Table[ANY_SIZE]; }
        // → Table 起点对齐到 MibIfRow2（8 字节）= offset 8（文档注明含 padding）。
        for (var i = 0; i < numEntries; i++) {
          final row = (table + kMibIfTable2RowsOffset + i * rowSize)
              .cast<MibIfRow2>()
              .ref;
          sum += row.inOctets;
        }
        return sum;
      } finally {
        _freeTable(table.cast());
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(out);
    }
  }
}

/// iOS/macOS：`getifaddrs` 遍历 AF_LINK 条目求和 `ifi_ibytes`（u32 口径，
/// 溢出由差分反跳兜底），排除 `lo`。
class DarwinRxCounter implements RxCounter {
  DarwinRxCounter();

  late final DynamicLibrary _lib = DynamicLibrary.process();
  late final int Function(Pointer<Pointer<DarwinIfaddrs>>) _getIfaddrs =
      _lib.lookupFunction<Int32 Function(Pointer<Pointer<DarwinIfaddrs>>),
          int Function(Pointer<Pointer<DarwinIfaddrs>>)>('getifaddrs');
  late final void Function(Pointer<DarwinIfaddrs>) _freeIfaddrs =
      _lib.lookupFunction<Void Function(Pointer<DarwinIfaddrs>),
          void Function(Pointer<DarwinIfaddrs>)>('freeifaddrs');

  @override
  int? readRxBytes() {
    final head = calloc<Pointer<DarwinIfaddrs>>();
    try {
      if (_getIfaddrs(head) != 0) return null;
      final first = head.value;
      if (first == nullptr) return null;
      try {
        var sum = 0;
        var node = first;
        while (node != nullptr) {
          final row = node.ref;
          final addr = row.ifaAddr;
          // BSD sockaddr：sa_len@0 + sa_family@1；仅 AF_LINK 的 ifa_data
          // 指向 struct if_data（AF_INET/AF_INET6 的 ifa_data 是别的结构）。
          if (addr != nullptr && addr.cast<Uint8>()[1] == kAfLink) {
            final name = row.ifaName.cast<Utf8>().toDartString();
            final data = row.ifaData;
            if (name != 'lo' && data != nullptr) {
              sum += data.cast<DarwinIfData>().ref.ifiIbytes;
            }
          }
          node = row.ifaNext;
        }
        return sum;
      } finally {
        _freeIfaddrs(first);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(head);
    }
  }
}

/// BSD AF_LINK 地址族值（macOS/iOS）。
const int kAfLink = 18;

/// `MIB_IF_TABLE2.Table[]` 相对表头的字节偏移（NumEntries 后的对齐 padding）。
const int kMibIfTable2RowsOffset = 8;

/// 反跳阈值：单 tick 差分超过 1GB/s 视为计数器重置（WiFi 重连等）。
const double kMaxPlausibleBps = 1000000000;

/// 真实下载速度计：按 [interval] 采样 [counter] 累计字节差分，
/// 经 [onSpeed] 回吐 每秒字节数（反跳 tick 回吐 0；不支持/连续失败回吐
/// null 并停止）。`null` 语义 = 当前无法给出速度（顶栏应隐藏）。
class NetworkSpeedMeter {
  NetworkSpeedMeter({
    required this.counter,
    required this.onSpeed,
    this.interval = const Duration(seconds: 1),
  });

  final RxCounter counter;
  final void Function(double? bytesPerSecond) onSpeed;
  final Duration interval;

  Timer? _timer;
  int? _prev;
  int _failures = 0;

  static const int _maxFailures = 3;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _prev = counter.readRxBytes();
    if (_prev == null) {
      // 首读即失败（平台不支持/权限）：不启动，明确回吐不可用。
      onSpeed(null);
      return;
    }
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _prev = null;
    _failures = 0;
  }

  void _tick() {
    final curr = counter.readRxBytes();
    if (curr == null) {
      _failures++;
      if (_failures >= _maxFailures) {
        stop();
        onSpeed(null);
      }
      return;
    }
    _failures = 0;
    final prev = _prev;
    _prev = curr;
    if (prev == null) return;
    final delta = curr - prev;
    // 负差分（u32 回绕/接口重置）或离谱值 → 本 tick 报 0，基线已更新。
    if (delta < 0 || delta > kMaxPlausibleBps * interval.inSeconds) {
      onSpeed(0);
      return;
    }
    onSpeed(delta / interval.inSeconds);
  }

  /// 字节数/秒 → `4.89 MB/s`（十进制 MB，两位小数）。
  static String formatMBs(double bytesPerSecond) =>
      '${(bytesPerSecond / 1000000).toStringAsFixed(2)} MB/s';

  /// 解析 `/proc/net/dev`：所有非 `lo` 接口 rx_bytes 求和；
  /// 无有效接口返回 null。
  static int? parseRxBytes(String content) {
    var total = 0;
    var found = false;
    for (final line in content.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim() == 'lo') continue;
      final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (fields.isEmpty) continue;
      final rx = int.tryParse(fields.first);
      if (rx == null) continue;
      total += rx;
      found = true;
    }
    return found ? total : null;
  }
}

/// 当前平台的累计收字节计数器；不支持的平台返回 null。
RxCounter? createDefaultRxCounter() {
  if (Platform.isAndroid || Platform.isLinux) return ProcNetDevRxCounter();
  if (Platform.isWindows) return WindowsRxCounter();
  if (Platform.isIOS || Platform.isMacOS) return DarwinRxCounter();
  return null;
}

// ---------------------------------------------------------------------------
// Windows：MIB_IF_TABLE2 / MIB_IF_ROW2（x64 布局，与 MSVC 一致：
// 字段全显式定宽，位域以 1 字节整数表达 + 自然对齐 padding）。
// ---------------------------------------------------------------------------

final class _Guid extends Struct {
  @Uint32()
  external int data1;

  @Uint16()
  external int data2;

  @Uint16()
  external int data3;

  @Array(8)
  external Array<Uint8> data4;
}

/// 对应 Windows `MIB_IF_ROW2`（读取 `inOctets` 所需的完整布局）。
final class MibIfRow2 extends Struct {
  @Uint64()
  external int interfaceLuid;

  @Uint32()
  external int interfaceIndex;

  external _Guid interfaceGuid;

  @Array(257)
  external Array<Uint16> alias;

  @Array(257)
  external Array<Uint16> description;

  @Uint32()
  external int physicalAddressLength;

  @Array(32)
  external Array<Uint8> physicalAddress;

  @Array(32)
  external Array<Uint8> permanentPhysicalAddress;

  @Uint32()
  external int mtu;

  @Uint32()
  external int type;

  @Int32()
  external int tunnelType;

  @Int32()
  external int mediaType;

  @Int32()
  external int physicalMediumType;

  @Int32()
  external int accessType;

  @Int32()
  external int directionType;

  /// InterfaceAndOperStatusFlags（8×1-bit 位域压成 1 字节，其后 pad 3）。
  @Uint8()
  external int interfaceAndOperStatusFlags;

  @Int32()
  external int operStatus;

  @Int32()
  external int adminStatus;

  @Int32()
  external int mediaConnectState;

  external _Guid networkGuid;

  @Int32()
  external int connectionType;

  @Uint64()
  external int transmitLinkSpeed;

  @Uint64()
  external int receiveLinkSpeed;

  @Uint64()
  external int inOctets;

  @Uint64()
  external int inUcastPkts;

  @Uint64()
  external int inNUcastPkts;

  @Uint64()
  external int inDiscards;

  @Uint64()
  external int inErrors;

  @Uint64()
  external int inUnknownProtos;

  @Uint64()
  external int inUcastOctets;

  @Uint64()
  external int inMulticastOctets;

  @Uint64()
  external int inBroadcastOctets;

  @Uint64()
  external int outOctets;

  @Uint64()
  external int outUcastPkts;

  @Uint64()
  external int outNUcastPkts;

  @Uint64()
  external int outDiscards;

  @Uint64()
  external int outErrors;

  @Uint64()
  external int outUcastOctets;

  @Uint64()
  external int outMulticastOctets;

  @Uint64()
  external int outBroadcastOctets;

  @Uint64()
  external int outQLen;
}

// ---------------------------------------------------------------------------
// Darwin（macOS/iOS）：struct ifaddrs / struct if_data（LP64 布局）。
// ---------------------------------------------------------------------------

/// 对应 BSD `struct ifaddrs`（LP64：56 字节，ifaFlags 后 4 字节 padding）。
final class DarwinIfaddrs extends Struct {
  external Pointer<DarwinIfaddrs> ifaNext;

  external Pointer<Uint8> ifaName;

  @Uint32()
  external int ifaFlags;

  external Pointer<Void> ifaAddr;

  external Pointer<Void> ifaNetmask;

  external Pointer<Void> ifaDstaddr;

  external Pointer<Void> ifaData;
}

/// 对应 BSD `struct if_data` 前缀（读取 `ifi_ibytes` 所需字段，
/// u_char/u_short/u_int 自然对齐 → ifiIbytes @32）。
final class DarwinIfData extends Struct {
  @Uint8()
  external int ifiType;

  @Uint8()
  external int ifiHdrlen;

  @Uint16()
  external int ifiMtu;

  @Uint32()
  external int ifiMetric;

  @Uint32()
  external int ifiBaudrate;

  @Uint32()
  external int ifiIpackets;

  @Uint32()
  external int ifiIerrors;

  @Uint32()
  external int ifiOpackets;

  @Uint32()
  external int ifiOerrors;

  @Uint32()
  external int ifiCollisions;

  @Uint32()
  external int ifiIbytes;
}

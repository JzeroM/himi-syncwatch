/// Optional MPV platform log sink.
///
/// Platform plugins cannot import the app's [LogService], so the app installs
/// a sink once and native-session adapters write through this shared hook.
typedef MpvLogSink = void Function(String tag, String message);

class MpvLog {
  const MpvLog._();

  static MpvLogSink? sink;

  static void log(String tag, String message) {
    final s = sink;
    if (s != null) {
      s(tag, message);
    }
  }
}

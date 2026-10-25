class TraktRateLimiter {
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  final Duration writeInterval;

  DateTime? _lastWrite;

  TraktRateLimiter({
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.writeInterval = const Duration(seconds: 1),
  })  : now = now ?? DateTime.now,
        delay = delay ?? Future<void>.delayed;

  Future<void> beforeWrite() async {
    final last = _lastWrite;
    if (last != null) {
      final elapsed = now().difference(last);
      if (elapsed < writeInterval) {
        await delay(writeInterval - elapsed);
      }
    }
    _lastWrite = now();
  }
}

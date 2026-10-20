enum TopBarClockFormat {
  off('off'),
  twelveHour('12h'),
  twentyFourHour('24h');

  const TopBarClockFormat(this.storageValue);

  final String storageValue;

  bool get enabled => this != off;

  static TopBarClockFormat fromStorage(Object? raw) {
    if (raw is String) {
      for (final format in values) {
        if (format.storageValue == raw) return format;
      }
    }
    return off;
  }
}

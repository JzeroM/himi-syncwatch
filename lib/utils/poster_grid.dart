int posterGridColumns({
  required double width,
  required bool tvMode,
  int? columns,
}) {
  final int target;
  if (columns != null) {
    target = columns;
  } else if (tvMode) {
    target = (width / 120).floor();
  } else if (width > 600) {
    target = (width / 180).floor();
  } else {
    target = 4;
  }

  final maxFit = (width / 80).floor();
  final upper = tvMode ? 14 : (width > 600 ? 12 : 6);
  final cap = maxFit > upper ? upper : maxFit;
  return target.clamp(1, cap < 1 ? 1 : cap);
}

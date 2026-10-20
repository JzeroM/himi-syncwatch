import 'dart:async';
import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/top_bar_clock_format.dart';

String formatPlayerClock(DateTime now, TopBarClockFormat format) {
  final minute = now.minute.toString().padLeft(2, '0');
  switch (format) {
    case TopBarClockFormat.twentyFourHour:
      return '${now.hour.toString().padLeft(2, '0')}:$minute';
    case TopBarClockFormat.twelveHour:
      final period = now.hour < 12 ? '上午' : '下午';
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      return '$period $hour:$minute';
    case TopBarClockFormat.off:
      return '';
  }
}

class PlayerClockLayer extends StatelessWidget {
  const PlayerClockLayer({
    super.key,
    required this.format,
    this.now,
    this.autoTick = true,
  });

  final TopBarClockFormat format;
  final DateTime Function()? now;
  final bool autoTick;

  @override
  Widget build(BuildContext context) {
    if (!format.enabled) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.paddingOf(context).top,
      left: 0,
      right: 0,
      height: 48,
      child: IgnorePointer(
        child: ExcludeFocus(
          child: Center(
            child: PlayerClock(
              format: format,
              now: now,
              autoTick: autoTick,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerClock extends StatefulWidget {
  const PlayerClock({
    super.key,
    required this.format,
    this.now,
    this.autoTick = true,
  });

  final TopBarClockFormat format;
  final DateTime Function()? now;
  final bool autoTick;

  @override
  State<PlayerClock> createState() => _PlayerClockState();
}

class _PlayerClockState extends State<PlayerClock> {
  Timer? _timer;
  late DateTime _now;

  DateTime _readNow() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _readNow();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant PlayerClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoTick != widget.autoTick) {
      _timer?.cancel();
      _scheduleTick();
    }
  }

  void _scheduleTick() {
    _timer?.cancel();
    if (!widget.autoTick) return;
    final now = _readNow();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final delay = nextMinute.difference(now) + const Duration(milliseconds: 50);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = _readNow());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatPlayerClock(_now, widget.format),
      key: const ValueKey('playerClock'),
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        fontFeatures: [FontFeature.tabularFigures()],
        shadows: [
          Shadow(color: Colors.black54, blurRadius: 4),
        ],
      ),
    );
  }
}

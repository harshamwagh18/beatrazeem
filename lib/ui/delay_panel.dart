import 'package:flutter/material.dart';
import '../audio/audio_timing.dart';
import 'design.dart';

class DelayPanel extends StatelessWidget {
  const DelayPanel({
    super.key,
    required this.timing,
    required this.active,
    required this.outputEnabled,
  });
  final AudioTiming timing;
  final bool active, outputEnabled;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final playing = active && outputEnabled;
    final delay = playing ? timing.delayMs : null;
    final delayText = !active
        ? 'Not playing'
        : !outputEnabled
        ? 'Output is off'
        : delay == null
        ? 'Measuring…'
        : '≈ ${delay.round()} ms';
    return Container(
      key: const ValueKey('live-delay'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Live delay',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Estimated playback delay',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            delayText,
            key: const ValueKey('playback-delay-value'),
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            !active
                ? 'Start audio to see this phone’s estimated playback delay.'
                : !outputEnabled
                ? 'Read Live delay on a joined phone that is playing.'
                : delay == null
                ? 'Waiting for fresh audio and speaker timing. Some phones cannot report playback delay.'
                : 'Estimated from audio timestamps, not a sound measurement. Bluetooth may add unreported delay.',
            style: TextStyle(color: c.muted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

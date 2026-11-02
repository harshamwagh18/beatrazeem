class AudioTiming {
  const AudioTiming({
    this.delayMs,
    this.offsetMs,
    this.measured = false,
    this.latePackets = 0,
    this.underruns = 0,
  });
  final double? delayMs;
  final double? offsetMs;
  final bool measured;
  final int latePackets;
  final int underruns;

  factory AudioTiming.fromMap(Map<String, dynamic> value) {
    final fresh =
        value['running'] == true &&
        value['timestampReady'] == true &&
        value['fresh'] == true;
    double? number(String key, {bool positive = false}) {
      final raw = value[key];
      if (!fresh ||
          raw is! num ||
          !raw.isFinite ||
          raw.abs() > 10000 ||
          (positive && raw < 0)) {
        return null;
      }
      return raw.toDouble();
    }

    return AudioTiming(
      delayMs: number('estimatedDelayMs', positive: true),
      offsetMs: number('timingOffsetMs'),
      measured: fresh,
      latePackets: (value['lateFrames'] is int ? value['lateFrames'] as int : 0)
          .clamp(0, 1000000),
      underruns: (value['underruns'] is int ? value['underruns'] as int : 0)
          .clamp(0, 1000000),
    );
  }
}

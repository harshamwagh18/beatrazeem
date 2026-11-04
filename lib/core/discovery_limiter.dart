import 'dart:math';

/// Bounds code guesses without retaining room codes or persistent IP logs.
class DiscoveryLimiter {
  DiscoveryLimiter({int Function()? nowMs}) {
    final watch = Stopwatch()..start();
    _nowMs = nowMs ?? () => watch.elapsedMilliseconds;
  }
  late final int Function() _nowMs;
  static const maxSources = 256;
  final Map<String, _SourceBudget> _sources = {};
  final _global = _Bucket(32, 500);
  int failedAttempts = 0, throttledRequests = 0;
  int get trackedSources => _sources.length;

  /// Zero permits a lookup; otherwise returns a bounded Retry-After in seconds.
  int admit(String source) {
    final now = _nowMs();
    _sources.removeWhere((_, value) => now - value.lastSeen >= 300000);
    var budget = _sources[source];
    if (budget == null) {
      if (_sources.length >= maxSources) return _deny(30);
      budget = _SourceBudget(now);
      _sources[source] = budget;
    }
    budget.lastSeen = now;
    final wait = max(
      max(budget.blockedUntil - now, budget.bucket.waitMs(now)),
      _global.waitMs(now),
    );
    if (wait > 0) return _deny(min(30, (wait / 1000).ceil()));
    budget.bucket.consume();
    _global.consume();
    return 0;
  }

  void recordResult(String source, {required bool matched}) {
    final budget = _sources[source];
    if (budget == null) return;
    if (matched) {
      budget.failures = 0;
      return;
    }
    failedAttempts = min(2147483647, failedAttempts + 1);
    budget.failures = min(8, budget.failures + 1);
    if (budget.failures >= 3) {
      budget.blockedUntil =
          _nowMs() + min(30000, 1000 << (budget.failures - 3));
    }
  }

  int _deny(int seconds) {
    throttledRequests = min(2147483647, throttledRequests + 1);
    return seconds;
  }
}

class _SourceBudget {
  _SourceBudget(this.lastSeen);
  final bucket = _Bucket(6, 5000);
  int lastSeen, failures = 0, blockedUntil = 0;
}

class _Bucket {
  _Bucket(this.capacity, this.refillMs) : tokens = capacity.toDouble();
  final int capacity, refillMs;
  double tokens;
  int lastRefill = 0;
  int waitMs(int now) {
    tokens = min(
      capacity.toDouble(),
      tokens + max(0, now - lastRefill) / refillMs,
    );
    lastRefill = now;
    return tokens >= 1 ? 0 : ((1 - tokens) * refillMs).ceil();
  }

  void consume() => tokens -= 1;
}

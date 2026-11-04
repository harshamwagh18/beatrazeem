# Validation — 4 November 2026, version 0.9.4 (build 20)

This release addresses BRZ-001 in the supplied audit. See [the audit response](SECURITY_AUDIT_REMEDIATION.md) for exact limits, source locations, skipped architectural changes and remaining exposure.

- **98 Flutter tests passed**, including eight new limiter/discovery security cases and the existing room, encryption, audio and UI regression suite. A first run exposed a test expectation mismatch: denial is a Dart StateError rather than Exception. Correcting the matcher confirmed the existing denial behavior; no admission bypass was observed.
- **Static analysis: no issues.**
- **Optimized ARM64 APK built successfully**, version 0.9.4 / 20, package com.beatrazeem.beatrazeem, minimum Android API 24, target API 35. App-audio capture/Karaoke still require Android 10+.
- **APK signature verified** with the existing development certificate SHA-256 `56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874`.

Tests cover per-source and aggregate budgets, source rotation, backoff and recovery, bounded bookkeeping, normal eight-source admission, real loopback HTTP guessing across fresh connections, client Retry-After behavior and denied room access after successful discovery without host approval. Counters contain no guessed codes or persistent IP log.

No native audio scheduling code changed. Previously completed native checks were not repeated; this is not a new physical-phone acoustic or performance measurement. Flooding can still delay new joins, and HTTP rate limits do not conceal multicast room advertisements or prevent port scans/raw connection flooding. This focused remediation is not a complete audit of every dependency or app subsystem.

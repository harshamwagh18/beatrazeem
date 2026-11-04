# Security audit response — 0.9.4 (build 20)

Reviewed 4 November 2026 against the supplied `audit-report.md`, which inspected commit `76165258b5f580b9af1b8d58e60524264f166b1d`. The working baseline was 0.9.3, commit `cfd263a4dcfa95136de63ae1dd76d815e93f2061`. Its discovery handler still had the reported issue.

## BRZ-001: confirmed and corrected

`lib/core/direct_discovery.dart` previously compared unlimited room-code guesses from reachable HTTP clients. The new `lib/core/discovery_limiter.dart` checks admission **before** inspecting the code and applies limits to successful and failed requests:

- Each source IP gets a burst of 6 requests, refilling one request every 5 seconds.
- All sources share a burst of 32 requests, refilling 2 requests per second. Changing source addresses therefore cannot bypass the overall lookup budget.
- After 3 failed admitted attempts from a source, its cooldown grows from 1 second to a maximum of 30 seconds. Requests denied during cooldown do not extend it. A successful admitted lookup clears the failure streak, but does not replenish either request budget.
- Requests beyond a limit return HTTP 429 with bounded Retry-After and no room code or port. Discovery responses prohibit caching and close the connection.
- A maximum of 256 source records are held in memory; idle records expire after 5 minutes. At capacity, unseen sources are temporarily denied instead of allocating more memory. Source records and counters are discarded when the room endpoint stops/restarts.
- Failed and throttled attempt counts are exposed through `failedDiscoveryAttempts` and `throttledDiscoveryRequests`. They are saturated aggregate diagnostics, not persistent logs or remote telemetry; guessed codes are not retained.
- The finder respects Retry-After. `lib/core/discovery.dart` reports temporary lookup limiting instead of a misleading generic room-not-found message when a search times out during backoff.

The regression file `test/discovery_limiter_test.dart` covers eight normal listeners, per-source/global budgets, rotating sources, cooldown/recovery, bounded memory, actual HTTP requests across new connections, client retry behavior, and refusal of room access after successful discovery when host approval is missing. The full Flutter suite passed **98 tests**.

## Compatibility and deliberately skipped changes

No confirmed finding was skipped: BRZ-001 can be mitigated while retaining the app's six-digit flow. The following optional architectural changes were not made:

| Suggested or related change | Reason for leaving it unchanged |
|---|---|
| Replace the six digits with a longer credential or require an additional discovery secret | This changes the requested six-digit-only joining experience and requires another secret-distribution flow. Rate limits reduce automated probing without adding that step. |
| Remove multicast discovery | This would remove the existing shared-Wi-Fi fallback used when direct hotspot/gateway lookup is unavailable. Multicast currently advertises the room code and port, so room metadata remains discoverable by reachable nearby devices. |
| Disable cleartext local carriers | This would break the current HTTP discovery and WebSocket carrier. The supplied report expressly withdrew its earlier claim that cleartext discovery itself bypassed peer verification. This update does not present cleartext as authentication: room content still requires mutual code comparison/approval and authenticated encryption. |

## Operational impact and remaining limits

Normal eight-listener discovery fits the configured burst budgets when devices have distinct local IPs. Repeated wrong codes, shared source addresses, global flooding or source-table exhaustion can temporarily delay **new joins**. Users receive a retry message where the direct endpoint reports throttling. Heavy ongoing traffic can continue to deny new discovery; this is not a denial-of-service-proof server. Existing audio streams, room clock processing and encrypted transport do not pass through this discovery limiter.

Limits apply to the HTTP code lookup, not multicast announcements, port scans, raw TCP connections, or all possible network attacks. The six digits remain a room locator, not a secret password or proof of peer identity. An attacker who already knows a code/port still encounters the existing encrypted approval handshake; this was regression-tested. Do not approve an unexpected device or skip comparing security codes.

This was a focused code remediation and host-network test run, not a complete new audit of every file/dependency or a physical multi-phone performance test. No guarantee of zero audio lag or complete absence of vulnerabilities is made.

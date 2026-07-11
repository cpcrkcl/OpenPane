# Phase 2 performance measurements

Measured on July 11, 2026 on the same Apple silicon Mac and Debug build. Each row uses the same temporary 10,000-file fixture and targeted XCTest harness before and after the Phase 2 changes. Timings are wall-clock measurements; small differences should be treated as noise.

| Workload | Phase 0 | Phase 2 | Result |
| --- | ---: | ---: | --- |
| Open 10k directory: first `items` publication | 292.95 ms | 214.24 ms | 26.9% faster |
| Open 10k directory: first `visibleItems` publication | 292.95 ms | 289.65 ms | 1.1% faster |
| Open 10k directory: metadata-ready completion | 293.04 ms | 289.68 ms | effectively unchanged |
| Assign five filter characters | 0.056 ms | 0.044 ms | effectively unchanged |
| Five-character filter: latest result published | 184.50 ms | 185.35 ms | effectively unchanged |
| Change sort direction: result published | 34.15 ms | 34.62 ms | effectively unchanged |
| Burst of five monitor events | 108.68 ms | 90.78 ms | 16.5% faster |
| Three rapid navigations | 12.32 ms | 12.37 ms | effectively unchanged; latest URL won |
| 200 icon keys, two passes | 8.37 ms | 13.11 ms | bounded bookkeeping adds 4.74 ms in this synthetic 200-key pass; no repeated misses |

## Instrumented work counts

| Counter | Phase 0 | Phase 2 |
| --- | ---: | ---: |
| Directory enumerations for 10k open | 1 | 1 |
| Full `items` replacements for no-op monitor refresh | 1 | 0 |
| `visibleItems` publications for no-op monitor refresh | 0 | 0 |
| Dual-pane fanouts for one selection plus one filter | 8 | 0 |
| Icon misses for 200 unique extensions over two passes | 200 | 200 |

The icon cache now has a default 256-entry bound. Background tab snapshots retain at most four tabs and at most 5,000 items per tab; larger or evicted snapshots reload when activated.

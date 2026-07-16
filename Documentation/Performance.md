# OpenPane performance architecture

Measurements were recorded on July 11, 2026 on the same Apple silicon Mac with a Debug build. The reproducible test creates a temporary directory containing 10,000 empty files, starts timing after fixture creation, and writes its latest result to `/tmp/OpenPanePerformanceBenchmark.json`. Final values below are the median of three isolated runs after one warm-up; filesystem-cache state can still move absolute timings, so the results are best treated as directional.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project OpenPane.xcodeproj -scheme OpenPane \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:OpenPaneTests/PerformanceBenchmarkTests
```

## Results

| Workload | Phase 0 | Final | Change |
| --- | ---: | ---: | ---: |
| First `items` publication for 10k files | 292.95 ms | 123.89 ms | 57.7% faster |
| First sorted `visibleItems` publication | 292.95 ms | 196.25 ms | 33.0% faster |
| Optional metadata-ready completion | 293.04 ms | 655.66 ms | intentionally later; no longer blocks first paint |
| Assign five filter characters | 0.056 ms | 0.044 ms | synchronous setter work remains negligible |
| Latest five-character filter result | 184.50 ms | 185.35 ms | effectively unchanged, including 150 ms debounce |
| Change sort direction | 34.15 ms | 34.62 ms | effectively unchanged |
| Burst of five unchanged monitor events | 108.68 ms | 76.49 ms | 29.6% faster; one fingerprint check and no array replacement |
| Three rapid navigations | 12.32 ms | 12.37 ms | effectively unchanged; latest URL wins |
| Recursive search for one match among 10k names | not recorded | 46.05 ms | full metadata built only for the match |

The metadata-ready number is not on the presentation critical path anymore. Rows first publish with stable URL identity plus name, directory, and hidden state. Size, modified date, and kind are enriched as one cancellable utility-priority batch. A future visible-row metadata pipeline could reduce that background total further, but was intentionally deferred to avoid destabilizing sorting, selection, Quick Look, and file operations.

## Core-workflow regression check

The focused 10,000-file benchmark was rerun on July 15, 2026 after adding contents search and byte-transfer progress. The directory pipeline remained on its established path: first `items` publication was 126.36 ms, first `visibleItems` publication was 196.15 ms, and a one-match recursive name search was 58.20 ms. Contents search is explicit and does no work during first paint; transfer preflight and callback handling run off the main actor.

The trailing preview also stays off the first-paint path. Quick Look is instantiated only for a previewable selection, lightweight metadata begins only after selection, and text bytes are not read until Edit is pressed. Selection work is delivered through a focused-item publisher instead of forwarding every arrow-key change through the dual-pane view model.

## Bottlenecks found and changes made

- Filtering and user-configurable sorting previously ran synchronously from `@Published` observers. They now use a 150 ms search debounce, cancellable background computation, generation checks, and main-actor publication of only the latest result.
- Directory entries were sorted once in `FileBrowserService` and again in the pane. The browser now returns unsorted lightweight entries and the pane owns the single presentation sort.
- Directory enumeration eagerly fetched and formatted every metadata field. Foreground snapshots now fetch essential keys only, publish, and enrich optional metadata afterward. Formatting is computed only when a displayed property is read.
- Icon cache misses called `NSWorkspace` from row evaluation and the cache was unbounded. Rows now render a placeholder immediately, consult a memory-only cache, and await a deduplicated utility-priority lookup.
- Dual-pane state forwarded every child `objectWillChange`, invalidating unrelated pane content. Parent publication is now limited to state the parent actually consumes.
- Monitor events always caused a full reload. Debounced events now obtain a constant-size, order-independent fingerprint over visible entry URLs and flags plus the directory modification marker. An unchanged fingerprint publishes nothing; a changed lightweight snapshot is reused directly by the refresh.
- Recursive search built a complete `FileItem` before checking its name. It now reads essential hidden/directory state, checks the filename, and builds extended metadata only for matches. Search runs at utility priority and remains cancellable.
- Content search streams local UTF-8 candidates in 64 KiB chunks with bounded carry-over rather than loading whole files. It is explicit (not part of the live filter), stops after 500 matches, and uses the same cancellation/generation checks as filename search.
- Byte-transfer callbacks are coalesced to at most ten UI progress updates per second, with immediate item-change and completion updates. Preflight byte counting runs off the main actor, so it does not affect directory first paint.
- Preview metadata loads use cancellation generations and a 64-entry revision cache. Format-specific inspection is scheduled only for the selected matching type, while text editing uses bounded 64 KiB reads and stops after 10 MiB plus one byte.
- Embedded movie previews request only Quick Look's cached/fast static thumbnail representation. Videos larger than 256 MiB skip AVFoundation duration and resolution inspection; playback remains opt-in through full Quick Look.
- Preview details use a native recycling table instead of a fully materialized nested SwiftUI text stack. Rows are reused while scrolling, and the table reloads only when the selected target or its metadata snapshot changes.

DEBUG diagnostics count visible-item computations/publications, directory enumerations, fingerprint checks/no-ops, icon misses, item-array replacements, and dual-pane fanouts. The benchmark and focused unit tests assert the important work counts in addition to wall-clock timing.

## Cache policy

| Cache | Key | Limit and eviction | Invalidation | Main-actor filesystem work |
| --- | --- | --- | --- | --- |
| File icons | directory, normalized extension, type identifier, or generic file | 256 entries and 4 MiB; deterministic FIFO bound plus `NSCache` pressure eviction | Explicit clear and warning/critical memory pressure | None. Reads only consult memory; deduplicated `NSWorkspace` lookup runs in an awaited utility task. |
| Folder sizes | standardized folder URL | 128 entries, LRU, 30-second TTL | TTL, explicit item/descendant invalidation after operations and refresh | None. Cached reads are URL dictionary lookups; validation and recursive calculation run off-main. |
| Open-With applications | type identifier or normalized extension | 64 entries, LRU | Pane lifetime and LRU eviction | None. A cache miss schedules one retained async Launch Services lookup per key and initially returns an empty result. |
| Background tab snapshots | tab UUID | Four background tabs; at most 5,000 items per cached tab | LRU eviction, dirty marking, navigation/session replacement | None. Snapshots contain already-published values; evicted or oversized tabs reload asynchronously. |
| Active directory fingerprint | current tab/directory | One constant-size signature | Every successful navigation or changed monitor snapshot | None during first publication. Signature and directory marker are computed in an awaited utility task after rows publish. |
| Preview metadata | file URL plus resource identity, size, and modification time | 64 entries, LRU | Revision changes and explicit invalidation after Quick Edit saves | None before selection. Core and lightweight format details load in cancellable detached work. |

## Correctness and remaining risks

- Every directory, metadata, filter, search, and monitor result is checked against generation, active tab, and URL before publication. Explicit navigation cancels monitor fingerprint work and supersedes older loads.
- Monitor fingerprints deliberately avoid a full incremental filesystem model. The two 64-bit order-independent entry accumulators, count, and directory modification date make accidental equality extremely unlikely, but a full diff engine would be stronger and substantially more invasive.
- Recursive search still uses `FileManager` enumeration rather than Spotlight, so a no-match search must walk the tree. It now avoids optional metadata work for those nonmatches.
- Content search intentionally does not use an index or impose a file-size cap; a no-match query can read every eligible file beneath the selected folder. Its chunked decoder keeps memory bounded.
- Mounted SMB Quick Edit relies on the mounted volume and macOS filesystem semantics. Disconnect or permission failures keep the original file and in-memory draft intact, but network latency still determines save completion time.
- Optional metadata enrichment is directory-wide rather than limited to visible rows. It is cancellable and off the first-paint path, but very large network directories can still take noticeable background time.
- Folder-size results can be stale for external nested changes for at most the 30-second TTL. OpenPane operations and manual refresh continue to invalidate affected descendants immediately.
- Icon and application discovery depend on legacy AppKit/Launch Services APIs. Their results are wrapped as immutable sendable values, all slow calls are kept off row/body evaluation, and the strict-concurrency application build is warning-free.

Historical Phase 0-to-Phase 2 measurements remain in `Documentation/Phase2Performance.md`.

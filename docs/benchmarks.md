# Scale measurements

Recorded on 2026-10-21 with Dart 3.12.0, macOS arm64, using
`flutter pub run tool/benchmark.dart`. These are one local JIT run, including
initial grammar setup in the first viewport. They are measurements, not CI
limits or promises for another machine.

| Operation | Milliseconds |
| --- | ---: |
| Construct and index 100,000 lines | 6.7 |
| Compile grammar and highlight the first 80 lines | 36.5 |
| Advance grammar state through the final viewport | 2,948.1 |
| Edit and incrementally update highlighting | 34.0 |
| Index the expanded 100,000-line diff | 2.7 |
| Compute 1,000 small file diffs | 22.1 |
| Index the 1,000-file patch | 5.5 |
| Look up a source line in each of 1,000 files | 14.7 |
| Highlight one changed line in each of 1,000 files | 34.4 |

The expanded diff exposes 100,002 rows using five compact blocks. The
1,000-file patch exposes 4,000 rows. The presentation cache retained eight
files with its capacity set to eight. A line unaffected by the edit retained
its original highlighted-line object. Process resident memory after the run
was approximately 182 MiB; that includes the JIT, grammar compilation and
retained source/token state, and is not a peak-memory measurement.

Flutter workflow tests assert fewer than 150 mounted `RichText` widgets for a
100,000-line read-only file, including a jump to line 90,001. They also exercise
variable-height annotations, source anchoring after insertions and synchronized
split scrolling. Terminal surfaces paint the visible terminal rows and tests
exercise resize and retained sessions.

Reaching a distant line in a stateful TextMate grammar still requires the
preceding grammar state. Use the background executor option for large files;
it produces viewport presentation without constructing offscreen spans.
`LiveHighlighter` retains per-line raw token state to make subsequent edits
incremental. The native Flutter editor uses a whole-document platform text
layout for IME while restricting colored spans to its viewport. Read-only
file and patch surfaces use indexed row virtualization.

Dart 3.9 native runtimes use individual pattern scanners because large combined
RegExp programs can crash that VM's JIT. Matching precedence is unchanged;
minimum-SDK conformance checks cover the fallback. This older runtime may have
different throughput from the measurements above.

A follow-up review run on the same SDK measured 4.0 ms for document indexing,
20.9 ms for the initial viewport, 2,527.7 ms to reach the final viewport,
19.9 ms for the incremental edit, 1.4 ms for the expanded layout, 10.2 ms to
compute 1,000 diffs, 2.4 ms to index them, 5.5 ms for source lookup, and
20.2 ms for highlighting. It retained the same five layout blocks, eight cached
files and unchanged highlighted-line identity, at approximately 183 MiB RSS.
These repeat measurements are observational and are not performance thresholds.

## Viewport reuse

On 2026-10-22, `flutter pub run tool/benchmark_viewport.dart` on Dart 3.12.0,
macOS arm64, measured this separate fixture of 100,000 event declarations:

| Window (80 output lines) | Milliseconds | Newly tokenized lines |
| --- | ---: | ---: |
| Initial viewport | 47.7 | 80 |
| First visit near line 90,001 | 5,144.3 | 90,000 |
| Scroll forward 20 lines | 2.0 | 20 |
| Return to the previous window | 0.5 | 0 |

The executor retained 180 raw token lines and 1,580 sparse grammar checkpoints.
Each retained document is capped at 512 token lines and 2,048 checkpoints;
there are at most four retained documents. The cold distant visit still
advances grammar state, without retaining tokens for all intervening lines.
These are one JIT run's observations, not frame times or CI timing limits.

The fixed-extent Flutter regression test jumps directly to line 90,001 and to
the final line, with fewer than 160 mounted `RichText` widgets including gutters.
A one-line scroll retains existing row elements and schedules no new highlight
request while inside the cached overscan window. Wrapped/annotated rows retain
their measured-layout tests. The browser demo runs this path with a persistent
worker and reports the actual visible range.

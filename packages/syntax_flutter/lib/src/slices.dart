import 'package:flutter/scheduler.dart';

/// How long a widget tokenizes while it builds. Most documents finish
/// within it, so they never show uncolored text.
const firstSliceBudget = Duration(milliseconds: 8);

/// How long each later slice runs between frames.
const sliceBudget = Duration(milliseconds: 4);

/// Runs [slice] with [sliceBudget] between frames until it returns true or
/// [stop] does, calling [onSlice] with its result after each run.
///
/// Slices run as scheduler tasks at animation priority, so they keep going
/// while the user scrolls, and a frame waits for at most one slice.
Future<void> tokenizeBetweenFrames({
  required bool Function(Duration budget) slice,
  required void Function(bool done) onSlice,
  required bool Function() stop,
}) async {
  while (!stop()) {
    final done = await SchedulerBinding.instance.scheduleTask(
      () => stop() || slice(sliceBudget),
      Priority.animation,
    );
    if (stop()) return;
    onSlice(done);
    if (done) return;
  }
}

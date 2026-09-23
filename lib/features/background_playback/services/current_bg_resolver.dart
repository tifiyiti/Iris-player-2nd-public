import 'package:flutter/material.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';
import 'package:provider/provider.dart';

/// The 副音 file that is actually loaded right now.
///
/// Three sources, most-authoritative first:
/// 1. [mappedFile] — an E-节 mapping segment is driving 副音, so THAT file is
///    the audible one even before the engine has re-opened on it;
/// 2. [engineFile] — the engine's own loaded file (only assigned once an open
///    succeeds, so it can lag a fresh mapping open);
/// 3. [naturalFile] — the natural queue's current entry, the last resort.
///
/// The editor previously consulted only the engine, so a mapping-driven (or
/// just-opened) bg showed as "no bg file" while it was audibly playing.
FileItem? resolveCurrentBgFile({
  required FileItem? mappedFile,
  required FileItem? engineFile,
  required FileItem? naturalFile,
}) =>
    mappedFile ?? engineFile ?? naturalFile;

/// Reactive [resolveCurrentBgFile]: rebuilds on store changes and on the
/// engine's FILE changing.
///
/// Selects the file only — a whole-engine `watch` would rebuild the caller on
/// every position/transport notification (several per second while playing).
FileItem? useCurrentBgFile(BuildContext context) {
  final bg = useBackgroundPlaybackStore();
  final mappedFile = bg.select(context, (s) => s.mappedFile);
  final queueSlice =
      bg.select(context, (s) => (index: s.currentIndex, queue: s.queue));
  final FileItem? engineFile = context
      .select<BackgroundPlaybackEngine, FileItem?>((e) => e.file);

  FileItem? natural;
  final int i = queueSlice.index;
  if (i >= 0 && i < queueSlice.queue.length) {
    natural = queueSlice.queue[i];
  }

  return resolveCurrentBgFile(
    mappedFile: mappedFile,
    engineFile: engineFile,
    naturalFile: natural,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/view/content/model/media_lib_content_mode.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Empty state for the library content browser.
///
/// Distinguishes "truly empty" (no rows at all — generic message) from
/// "filtered empty" (rows exist but the pathTree "only dirs with media"
/// filter hid every directory — message plus a one-tap "show all" action).
/// The unfiltered probe runs only when this widget is actually displayed, so
/// the steady-state browsing cost is zero.
class LibContentEmptyState extends HookWidget {
  const LibContentEmptyState({super.key, required this.store});

  final MediaLibContentStore store;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final viewMode = store.select(context, (s) => s.viewMode);
    final hideEmpty = store.select(context, (s) => s.pathTreeHideEmpty);
    final storageId = store.select(context, (s) => s.currentStorageId);
    final parentPath = store.select(context, (s) => s.currentParentPath);

    Widget generic() => Center(
          child: Text(
            t.browser_empty,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        );

    // The filter only applies to pathTree source content; everywhere else
    // (sources page, allMedia, allDirs) an empty list is truly empty.
    if (viewMode != MediaLibContentMode.pathTree ||
        !hideEmpty ||
        storageId == null) {
      return generic();
    }

    final probe = useFuture(
      useMemoized(
        () => store.pathTreeHasUnfilteredRows(),
        [storageId, parentPath, hideEmpty],
      ),
    );
    if (probe.data != true) return generic();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.lib_empty_filtered_no_media,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => store.updatePathTreeHideEmpty(false),
            child: Text(t.lib_show_all_dirs),
          ),
        ],
      ),
    );
  }
}

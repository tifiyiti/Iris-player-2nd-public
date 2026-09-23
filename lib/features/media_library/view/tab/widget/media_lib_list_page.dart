import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/view/tab/store/libs/enum/load_state.dart';
import 'package:iris/features/media_library/view/tab/store/libs/use_media_libs_page_store.dart';
import 'package:iris/features/media_library/view/tab/store/selection/use_media_lib_selection.dart';
import 'package:iris/features/media_library/view/tab/widget/media_lib_tile.dart';
import 'package:iris/utils/get_localizations.dart';

class MediaLibListPage extends HookWidget {
  const MediaLibListPage({
    super.key,
    this.onTapOpen,
  });

  final void Function(String libraryId)? onTapOpen;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final store = useMediaLibsStore();
    final libraries = store.select(
      context,
      (s) => s.runtime.libraries,
    );
    final runtime = store.select(context, (s) => s.runtime);

    switch (runtime.state) {
      case LoadState.initial:
      case LoadState.loading:
        return const Center(
          child: CircularProgressIndicator(),
        );

      case LoadState.error:
        return Center(
          child: Text(t.lib_load_error),
        );

      case LoadState.ready:
        if (runtime.libraries.isEmpty) {
          return Center(
            child: Text(t.lib_no_libraries),
          );
        }

        // If we are NOT loading and still have no data, it truly is empty.
        if (libraries.isEmpty) {
          return Center(
            child: Text(t.lib_no_libraries),
          );
        }

        final selectionStore = useMediaLibSelectionStore();
        final selection = selectionStore.controller;
        // Extract list of IDs for the controller to perform range calculations
        final ids = libraries.map((e) => e.id).toList();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: libraries.length,
          itemBuilder: (_, i) {
            final lib = libraries[i];
            return MediaLibTile(
              onLongPress: () => selectionStore.controller.longPressAt(lib.id, ids),
              library: libraries[i],
              selection: selection,
              onTileTap: onTapOpen,
            );
          },
        );
    }
  }
}

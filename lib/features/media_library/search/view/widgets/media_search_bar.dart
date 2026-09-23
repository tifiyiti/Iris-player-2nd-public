import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/store/use_media_lib_search_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Android-Studio-style inline search bar (F-004): text field + clear button
/// (shown when non-empty) + history dropdown. Occupies the breadcrumb slot via
/// `PaginatedBrowserPage.headerOverride`.
class MediaSearchBar extends HookWidget {
  final MediaSearchDataSource dataSource;

  const MediaSearchBar({super.key, required this.dataSource});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final searchStore = useMediaLibSearchStore();
    final history = searchStore.select(context, (s) => s.history);
    // v11-D4: seed from the data source so a resumed (parked) session shows its
    // query instead of an empty field. useTextEditingController creates the
    // controller once with this initial text; a fresh page has query == ''.
    final controller = useTextEditingController(text: dataSource.query);
    final hasText = useState(dataSource.query.isNotEmpty);

    // v8-D2: focus the search field on entry and pop the IME. `autofocus: true`
    // alone loses the race against the Popup's outer KeyboardListener
    // (`autofocus: true` for desktop Escape); a post-frame requestFocus runs
    // after it and reliably grabs focus.
    final focusNode = useFocusNode();
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.hasFocus) return;
        focusNode.requestFocus();
      });
      return null;
    }, [focusNode]);

    void handleChanged(String value) {
      // NFR-006: skip query while an IME (Chinese/Japanese) is still composing.
      if (controller.value.isComposingRangeValid) return;
      hasText.value = value.isNotEmpty;
      dataSource.updateQuery(value);
    }

    void handleSubmit(String value) {
      dataSource.submitQuery(value);
    }

    void handleClear() {
      controller.clear();
      hasText.value = false;
      dataSource.clearQuery();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: t.search_bar_hint,
              ),
              onChanged: handleChanged,
              onSubmitted: handleSubmit,
            ),
          ),
          if (hasText.value)
            IconButton(
              tooltip: t.search_bar_clear,
              icon: const Icon(Icons.close, size: 18),
              onPressed: handleClear,
            ),
          PopupMenuButton<String>(
            tooltip: t.search_bar_history,
            icon: const Icon(Icons.history, size: 20),
            onSelected: (value) async {
              if (value == _kClearAll) {
                await searchStore.clearHistory();
                return;
              }
              // v6-D6: history click fills the field and searches immediately.
              controller.text = value;
              controller.selection = TextSelection.collapsed(offset: value.length);
              hasText.value = true;
              await dataSource.applyHistoryEntry(value);
            },
            itemBuilder: (_) => [
              if (history.isEmpty)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(t.search_bar_no_history),
                )
              else ...[
                for (final entry in history.take(10))
                  PopupMenuItem<String>(
                    value: entry,
                    child: Row(
                      children: [
                        const Icon(Icons.manage_search, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(entry, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: _kClearAll,
                  child: Row(
                    children: [
                      const Icon(Icons.delete_sweep_outlined, size: 16),
                      const SizedBox(width: 8),
                      Text(t.search_bar_clear_all),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static const String _kClearAll = '__clear_all__';
}

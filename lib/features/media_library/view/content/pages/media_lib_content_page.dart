import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/media_library/view/content/data_source/lib_content_data_source.dart';
import 'package:iris/features/media_library/view/content/model/lib_content_item.dart';
import 'package:iris/features/media_library/view/content/pages/lib_content_empty_state.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';

class MediaLibContentPage extends HookWidget {
  const MediaLibContentPage({
    super.key,
    required this.onBack,
    this.onClose,
    this.onHomePage,
  });

  final VoidCallback onBack;
  final VoidCallback? onClose;
  final VoidCallback? onHomePage;

  @override
  Widget build(BuildContext context) {
    final store = useMediaLibContentStore();
    final dataSource = useMemoized(() => LibContentDataSource(store));
    final controller = useMemoized(
      () => PaginatedBrowserController<LibContentItem>(),
    );

    // First render must use the persisted state (viewMode, filters, ...), so
    // wait for the store's async load before refreshing — otherwise the page
    // would briefly render in the default (pathTree) mode.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await store.initialized;
        store.refresh();
      });
      return null;
    }, []);

    // When a scan completes, refresh the content so updated aggregates
    // and newly discovered nodes are visible immediately.
    useEffect(() {
      final scanStore = useRecursiveScanStore();
      ScanPhase? prevPhase = scanStore.state.phase;
      final sub = scanStore.stream.listen((state) {
        final wasScanning = prevPhase == ScanPhase.scanning;
        prevPhase = state.phase;
        if (wasScanning &&
            (state.phase == ScanPhase.done ||
             state.phase == ScanPhase.stopped)) {
          store.refresh();
        }
      });
      return sub.cancel;
    }, []);

    return PaginatedBrowserPage<LibContentItem>(
      dataSource: dataSource,
      controller: controller,
      onClose: onClose,
      onHomePage: onHomePage ?? onBack,
      emptyStateOverride: LibContentEmptyState(store: store),
    );
  }
}

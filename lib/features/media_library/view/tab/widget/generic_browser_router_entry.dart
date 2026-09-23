import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/data_source/mock_browser_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';

class GenericBrowserRouterEntry extends HookWidget {
  const GenericBrowserRouterEntry({
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
    final dataSource = useMemoized(() => MockBrowserDataSource());
    final controller = useMemoized(
      () => PaginatedBrowserController<MockItemEntity>(),
    );

    useListenable(controller);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => dataSource.fetchPage(0, dataSource.pageSize),
      );
      return null;
    }, []);

    return PaginatedBrowserPage<MockItemEntity>(
      dataSource: dataSource,
      controller: controller,
      onClose: onClose,
      onHomePage: onHomePage ?? onBack,
    );
  }
}

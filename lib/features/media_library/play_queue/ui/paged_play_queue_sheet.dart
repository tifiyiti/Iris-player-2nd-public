import 'package:flutter/material.dart';
import 'package:iris/features/media_library/play_queue/data_source/paged_play_queue_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/models/file.dart';
import 'package:iris/widgets/popup.dart';

void showPagedPlayQueueSheet(
  BuildContext context, {
  required PopupDirection direction,
}) {
  final dataSource = PagedPlayQueueDataSource();

  showPopup(
    context: context,
    direction: direction,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: PaginatedBrowserPage<PlayQueueItem>(
            dataSource: dataSource,
            onClose: () => Navigator.pop(context),
            showHomePage: false,
            showBackButton: false,
          ),
        ),
      ],
    ),
  );
}

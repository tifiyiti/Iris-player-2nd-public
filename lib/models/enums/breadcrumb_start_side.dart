import 'package:iris/l10n/app_localizations.dart';

enum BreadcrumbStartSide {
  left,
  right,
}

extension BreadcrumbStartSideLabel on BreadcrumbStartSide {
  String label(AppLocalizations t) {
    switch (this) {
      case BreadcrumbStartSide.left:
        return t.breadcrumb_start_left;
      case BreadcrumbStartSide.right:
        return t.breadcrumb_start_right;
    }
  }
}

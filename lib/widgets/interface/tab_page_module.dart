import 'package:flutter/material.dart';

abstract class TabPageModule {
  /// Localized tab title
  String title(BuildContext context);

  /// Tab content
  Widget buildPage(BuildContext context);

  /// Optional action widget shown in the bottom bar when this tab is active
  Widget? buildAction(BuildContext context);
}

import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';
import 'package:iris/widgets/popups/storages/favorites.dart';

class FavoritesTabPage implements TabPageModule {
  @override
  String title(BuildContext context) => getLocalizations(context).favorites;

  @override
  Widget buildPage(BuildContext context) => const Favorites();

  @override
  Widget? buildAction(BuildContext context) => null;
}

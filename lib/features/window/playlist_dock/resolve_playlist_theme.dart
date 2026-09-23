import 'package:flutter/material.dart';
import 'package:iris/models/store/app_state.dart';

/// PotPlayer 深色 palette (Image 1 参考) — 固定深色，不跟随系统
const Color kPotlikeSurface = Color(0xFF1E1E1E);
const Color kPotlikeHeader = Color(0xFF252525);
const Color kPotlikeDivider = Color(0xFF333333);
const Color kPotlikeText = Color(0xFFE0E0E0);
const Color kPotlikeSubText = Color(0xFFAAAAAA);

ThemeData potlikeDarkTheme() => ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kPotlikeSurface,
      colorScheme: const ColorScheme.dark(
        surface: kPotlikeSurface,
        primary: Color(0xFF0078D4),
      ),
      dividerColor: kPotlikeDivider,
    );

/// Resolve floating popup theme: system follows [ThemeMode]/[Brightness].
ThemeData resolvePlaylistPopupTheme(
  BuildContext context,
  PlaylistPopupTheme setting, {
  required ThemeMode appThemeMode,
}) {
  switch (setting) {
    case PlaylistPopupTheme.light:
      return ThemeData.light();
    case PlaylistPopupTheme.dark:
      return ThemeData.dark();
    case PlaylistPopupTheme.system:
      final brightness = Theme.of(context).brightness;
      // Follow app's effective brightness; Theme already resolved system.
      return brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  }
}

/// Resolve dock (side) theme. `potlikeDark` is fixed PotPlayer style.
ThemeData resolvePlaylistDockTheme(
  BuildContext context,
  PlaylistDockTheme setting,
) {
  switch (setting) {
    case PlaylistDockTheme.light:
      return ThemeData.light();
    case PlaylistDockTheme.system:
      final brightness = Theme.of(context).brightness;
      return brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    case PlaylistDockTheme.potlikeDark:
      return potlikeDarkTheme();
  }
}

/// Whether the resolved theme is dark — used for splitter/divider tint.
bool isThemeDark(ThemeData theme) => theme.brightness == Brightness.dark;

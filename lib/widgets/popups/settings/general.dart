import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/languages.dart';
import 'package:iris/pages/player/control_bar/title_overlay_config_ialog.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/features/media_library/scan/view/scan_auto_close_settings_dialog.dart';
import 'package:iris/features/settings_transfer/view/export_dialog.dart' show showTransferExportDialog;
import 'package:iris/features/settings_transfer/view/import_dialog.dart' show showTransferImportDialog;
import 'package:iris/widgets/dialogs/open_breadcrumb_settings.dart' show openBreadcrumbSettings;
import 'package:iris/widgets/dialogs/show_enum_radio_dialog.dart' show showEnumRadioDialog;
import 'package:iris/widgets/dialogs/show_language_dialog.dart';
import 'package:iris/widgets/dialogs/show_legacy_compat_dialog.dart';
import 'package:iris/widgets/dialogs/show_theme_mode_dialog.dart';
import 'package:iris/widgets/popup.dart' show PopupDirection, PopupDirectionLocalization;

class General extends HookWidget {
  const General({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final language = useAppStore().select(context, (state) => state.language);
    final themeMode = useAppStore().select(context, (state) => state.themeMode);
    final popupDirection = useAppStore().select(context, (s) => s.defaultPopupDirection);
    final metaSettingsOn =
        useAppStore().select(context, (s) => s.useMetadataSettings);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Legacy 兼容收拢弹窗：主闸 + 双写策略 + 三个旧版开关集中一处
          // （与 meta 页的 legacy.compatEntry 共用同一 dialog）。
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(t.set_legacy_compat_row),
            subtitle: Text(metaSettingsOn
                ? t.ed_mode_meta
                : t.ed_mode_legacy),
            onTap: () => showLegacyCompatDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(t.language),
            subtitle: Text(language == 'system' ? t.system : languages[language] ?? language),
            onTap: () => showLanguageDialog(context),
          ),
          ListTile(
            leading: Icon(themeMode == ThemeMode.light
                ? Icons.light_mode_rounded
                : themeMode == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : Icons.contrast_rounded),
            title: Text(t.theme_mode),
            subtitle: Text(() {
              switch (themeMode) {
                case ThemeMode.system:
                  return t.system;
                case ThemeMode.light:
                  return t.light;
                case ThemeMode.dark:
                  return t.dark;
              }
            }()),
            onTap: () => showThemeModeDialog(context),
          ),
          // Transfer entries are cross-platform (v2 engine + file_picker run
          // on desktop too); the remaining rows below stay mobile-only.
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_rounded),
            title: Text(t.export_label),
            subtitle: Text(t.export_options),
            onTap: () => showTransferExportDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(t.import_label),
            subtitle: Text(t.import_options),
            onTap: () => showTransferImportDialog(context),
          ),
          if (Platform.isAndroid) ...[
            ListTile(
              leading: const Icon(Icons.title),
              title: Text(t.controls_title_settings),
              subtitle: Text(t.configure_controls_title),
              onTap: () {
                final store = useAppStore();
                showTitleOverlayConfigDialog(
                  context: context,
                  title: t.controls_title_settings,
                  initial: store.state.controlsTitleConfig,
                  onConfirmed: (c) => store.updateControlsTitleConfig(c),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(t.minimal_title_settings),
              subtitle: Text(t.configure_minimal_title),
              onTap: () {
                final store = useAppStore();
                showTitleOverlayConfigDialog(
                  context: context,
                  title: t.minimal_title_settings,
                  initial: store.state.minimalTitleConfig,
                  onConfirmed: (c) => store.updateMinimalTitleConfig(c),
                );
              },
            ),
            if (isMobilePlatform)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(t.popup_direction),
                subtitle: Text(popupDirection.label(t)),
                onTap: () => showEnumRadioDialog<PopupDirection>(
                  context: context,
                  title: t.popup_direction,
                  values: PopupDirection.values,
                  currentValue: popupDirection,
                  labelOf: (v) => v.label(t),
                  onSelected: (v) => useAppStore().updateDefaultPopupDirection(v),
                ),
              ),
            if (isMobilePlatform)
              ListTile(
                leading: const Icon(Icons.sync_alt),
                title: Text(t.breadcrumb_start_side),
                subtitle: Text(t.breadcrumb_start_side_desc),
                onTap: () => openBreadcrumbSettings(context),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Scan auto-close'),
            subtitle: const Text('Time to wait before closing scan progress'),
            onTap: () => openScanAutoCloseSettings(context),
          ),
        ],
      ),
    );
  }
}

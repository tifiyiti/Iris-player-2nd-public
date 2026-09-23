import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart'
    show SortDirection;
import 'package:iris/features/media_library/model/enum/media_node.dart'
    show MediaSortField;
import 'package:iris/features/scenario_playback/actions/scenario_append_actions.dart';
import 'package:iris/features/scenario_playback/actions/scenario_managed_play_actions.dart';
import 'package:iris/features/scenario_playback/actions/scenario_override_actions.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart'
    show ScenarioSourceSpec;
import 'package:iris/features/scenario_playback/actions/scenario_playback_error.dart';
import 'package:iris/features/scenario_playback/actions/scenario_resolved_actions.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_sort_spec.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart' show SortBy, SortOrder;
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';
import 'package:iris/widgets/dialogs/show_no_media_confirm_dialog.dart';

export 'scenario_playback_common.dart'
    show ScenarioSourceSpec, ensurePlaybackWorkspace;
export 'scenario_playback_error.dart' show PlaybackUnavailableException;

/// Outcome of [ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm] — lets
/// callers distinguish a normal (playable) success from a forced No-Media retry
/// so the storagedb popup close stays correct (success closes; forced keeps the
/// popup, v3-D6/v6-D36).
enum NoMediaActionResult {
  /// Completed on the first attempt (content was playable).
  success,

  /// No Media was confirmed and the action ran via a forced retry; the popup
  /// must stay open (workspace installed / empty append, nothing plays).
  forced,

  /// The No Media dialog was dismissed — nothing changed.
  cancelled,

  /// A non-NoMedia failure surfaced (uniform error dialog shown).
  failed,
}

/// High-level play actions that route the main playback flows (storage
/// browser, media library content, media search, scenario pages) through the
/// scenario-driven system.
///
/// Design (E1/D2): playing a folder/library OVERRIDES the SystemPlayingScenario
/// workspace — sources/explicit/temporary excludes/persistent excludes are all
/// cleared and the new scope installed. The current item is the tapped file.
///
/// This class is a thin facade: the actual behavior lives in the focused
/// modules under `actions/` (override / append / resolved). Keeping the single
/// facade lets every surface share one import + the sort-mapping helpers.
class ScenarioPlaybackActions {
  const ScenarioPlaybackActions._();

  /// Plays [tapped] with the effective queue being the given folder scope —
  /// the unified click entry for storagedb files-paged AND media-lib content
  /// taps. See [ScenarioOverrideActions.playFolderScopeInDefaultScenario].
  static Future<void> playFolderScopeInDefaultScenario({
    required String storageId,
    required String folderPath,
    required FileItem tapped,
    String? itemPath,
    bool recursive = false,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    bool force = false,

    /// When non-null, the recursive-scan gate runs for recursive scopes
    /// (files-page / storages-list / lib-tile / lib-content surfaces).
    BuildContext? gateContext,
  }) =>
      ScenarioOverrideActions.playFolderScopeInDefaultScenario(
        storageId: storageId,
        folderPath: folderPath,
        tapped: tapped,
        itemPath: itemPath,
        recursive: recursive,
        sortField: sortField,
        sortDirection: sortDirection,
        force: force,
        gateContext: gateContext,
      );

  /// Plays a multi-selection (files-paged / lib content / search) through the
  /// SystemPlaying workspace. See
  /// [ScenarioOverrideActions.playSelectionInDefaultScenario].
  static Future<void> playSelectionInDefaultScenario({
    required List<FileItem> files,
    required List<ScenarioSourceSpec> directories,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    bool force = false,

    /// When non-null, the recursive-scan gate runs for recursive dirs
    /// (files-page / storages-list / lib-tile / lib-content surfaces).
    BuildContext? gateContext,
  }) =>
      ScenarioOverrideActions.playSelectionInDefaultScenario(
        files: files,
        directories: directories,
        sortField: sortField,
        sortDirection: sortDirection,
        force: force,
        gateContext: gateContext,
      );

  /// OVERRIDES the SystemPlaying workspace with [files] as explicit items only
  /// and plays from the first available one (no directories). See
  /// [ScenarioOverrideActions.playFilesOverride].
  static Future<void> playFilesOverride({
    required List<FileItem> files,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
  }) =>
      ScenarioOverrideActions.playFilesOverride(
        files: files,
        sortField: sortField,
        sortDirection: sortDirection,
      );

  /// Appends files (+ optional source directories, F-009) to the
  /// SystemPlayingScenario as explicit items without clearing the current
  /// scope. See [ScenarioAppendActions.appendToDefaultScenario].
  static Future<void> appendToDefaultScenario(
    List<FileItem> files, {
    List<ScenarioSourceSpec> directories = const [],
  }) =>
      ScenarioAppendActions.appendToDefaultScenario(
        files,
        directories: directories,
      );

  /// Appends files (+ optional source directories, F-009) to the
  /// SystemPlayingScenario and shows a before/after feedback dialog (v14-D2).
  /// See [ScenarioAppendActions.appendToDefaultScenarioWithFeedback].
  static Future<void> appendToDefaultScenarioWithFeedback(
    BuildContext context,
    List<FileItem> files, {
    List<ScenarioSourceSpec> directories = const [],
  }) =>
      ScenarioAppendActions.appendToDefaultScenarioWithFeedback(
        context,
        files,
        directories: directories,
      );

  /// Plays a resolved effective item through the SystemPlaying workspace.
  /// See [ScenarioResolvedActions.playResolvedItem].
  static Future<void> playResolvedItem(
    BuildContext context, {
    required PlaybackScenarioStore store,
    required String scenarioId,
    required EffectivePlaybackItem item,
    ScenarioSortSpec? previewSort,
    bool forceConfirmIfNotPlaying = false,
    String? vmStartMediaKey,
    int? vmStartOccurrenceIndex,
    VoidCallback? onExitAfterPlay,
  }) =>
      ScenarioResolvedActions.playResolvedItem(
        context,
        store: store,
        scenarioId: scenarioId,
        item: item,
        previewSort: previewSort,
        forceConfirmIfNotPlaying: forceConfirmIfNotPlaying,
        vmStartMediaKey: vmStartMediaKey,
        vmStartOccurrenceIndex: vmStartOccurrenceIndex,
        onExitAfterPlay: onExitAfterPlay,
      );

  /// Starts playback of the SystemPlaying workspace from its current item.
  static Future<void> playCurrentWorkspace({String? scenarioId}) =>
      ScenarioResolvedActions.playCurrentWorkspace(scenarioId: scenarioId);

  /// Plays the scenario whose manager is open (browse page Play action): direct
  /// play when it is the live workspace, else Override + play. See
  /// [ScenarioManagedPlayActions.playManagedScenario].
  static Future<void> playManagedScenario(
    BuildContext context, {
    required String scenarioId,
    VoidCallback? onExitAfterPlay,
  }) =>
      ScenarioManagedPlayActions.playManagedScenario(
        context,
        scenarioId: scenarioId,
        onExitAfterPlay: onExitAfterPlay,
      );

  /// Restores the last playing item into the player on app start.
  static Future<void> resumeScenarioPlayback() =>
      ScenarioResolvedActions.resumeScenarioPlayback();

  /// Switches the player to [scenarioId]'s own context (current item, or blank
  /// when empty). See [ScenarioResolvedActions.switchPlaybackContext].
  static Future<void> switchPlaybackContext(
    String scenarioId, {
    bool autoplay = true,
  }) =>
      ScenarioResolvedActions.switchPlaybackContext(scenarioId,
          autoplay: autoplay);

  /// Maps the files-paged sort state to a scenario sort field.
  static ScenarioSortField scenarioSortFieldFrom(SortBy sortBy) {
    switch (sortBy) {
      case SortBy.name:
        return ScenarioSortField.name;
      case SortBy.size:
        return ScenarioSortField.sizeInBytes;
      case SortBy.lastModified:
        return ScenarioSortField.modifiedAt;
    }
  }

  /// Maps the lib-content sort field to a scenario sort field.
  static ScenarioSortField scenarioSortFieldFromMedia(MediaSortField field) {
    switch (field) {
      case MediaSortField.name:
        return ScenarioSortField.name;
      case MediaSortField.createdAt:
        return ScenarioSortField.name;
      case MediaSortField.modifiedAt:
        return ScenarioSortField.modifiedAt;
      case MediaSortField.durationMs:
        return ScenarioSortField.durationMs;
      case MediaSortField.sizeInBytes:
        return ScenarioSortField.sizeInBytes;
      default:
        return ScenarioSortField.name;
    }
  }

  /// Converts a files-paged [SortOrder] to a scenario [SortDirection].
  static SortDirection scenarioSortDirectionFrom(SortOrder order) =>
      order == SortOrder.asc ? SortDirection.asc : SortDirection.desc;

  /// First-use explainer of the scenario "workspace" model. Suppressible with
  /// the "don't show again" box ticked by default; restore it from
  /// Settings → Warning dialogs. [show] lets widget tests skip the modal.
  ///
  /// Returns false when the user CANCELS: the notice sits in front of a write
  /// to the playing workspace, so an acknowledgement-only dialog would trap the
  /// user in the play they wanted to abort. A suppressed notice returns true
  /// (auto-continue), preserving the old behavior.
  static Future<bool> _maybeShowWorkspaceNotice(
    BuildContext context, {
    required bool show,
  }) async {
    if (!show) return true;
    final t = getLocalizations(context);
    return showConfirmSuppressibleDialog(
      context,
      warningId: kWarningScenarioWorkspace,
      title: t.dlg_warn_scenario_workspace_title,
      message: t.dlg_scenario_workspace_body,
      confirmLabel: t.ok,
      cancelLabel: t.cancel,
      defaultDontAsk: true,
    );
  }

  /// Runs a play action and surfaces any failure as the uniform copyable error
  /// dialog (v15-D6). The player/workspace are left untouched by the throwing
  /// action (override actions validate before commit). Returns true when the
  /// action completed without throwing.
  static Future<bool> runPlayAction(
    BuildContext context,
    Future<void> Function() action, {
    /// When true (default) show the first-use workspace-override explainer
    /// before running the action. Tests pass false to skip the modal.
    bool showWorkspaceNotice = true,
  }) async {
    final proceed =
        await _maybeShowWorkspaceNotice(context, show: showWorkspaceNotice);
    if (!proceed) return false;
    if (!context.mounted) return false;
    try {
      await action();
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final t = getLocalizations(context);
      final message = e is PlaybackUnavailableException
          ? e.displayMessage(t)
          : t.dlg_play_failed_prefix('$e');
      await showCopyableErrorDialog(
        context,
        title: t.dlg_copy_error_title,
        message: message,
      );
      return false;
    }
  }

  /// Shared No Media 分流 helper (v4-D9/D15): runs [action] with `force:false`;
  /// a [PlaybackUnavailableException] is routed to `showNoMediaConfirmDialog`
  /// (confirm → the action is retried with `force:true`, cancel → no-op);
  /// every other failure surfaces the uniform error dialog. F-001…F-007 all
  /// route through here so no call site re-implements the try/catch split.
  ///
  /// [append] switches the confirm button wording to 「强制空追加」(D29); the
  /// retry must therefore run the WITH-feedback empty-append variant.
  static Future<NoMediaActionResult> runPlayActionWithNoMediaConfirm(
    BuildContext context, {
    required Future<void> Function({bool force}) action,
    bool append = false,

    /// When true (default) show the first-use workspace-override explainer
    /// before a non-append action. Tests pass false to skip the modal.
    bool showWorkspaceNotice = true,
  }) async {
    if (!append) {
      final proceed =
          await _maybeShowWorkspaceNotice(context, show: showWorkspaceNotice);
      // Cancel means "do not play" — same outcome as dismissing the No Media
      // confirm (nothing changed).
      if (!proceed) return NoMediaActionResult.cancelled;
      if (!context.mounted) return NoMediaActionResult.cancelled;
    }
    try {
      await action(force: false);
      return NoMediaActionResult.success;
    } on PlaybackUnavailableException {
      if (!context.mounted) return NoMediaActionResult.cancelled;
      final confirmed = await showNoMediaConfirmDialog(
        context,
        confirmLabel:
            append ? getLocalizations(context).dlg_force_append : null,
      );
      if (!confirmed || !context.mounted) return NoMediaActionResult.cancelled;
      try {
        await action(force: true);
        return NoMediaActionResult.forced;
      } catch (e) {
        if (!context.mounted) return NoMediaActionResult.failed;
        final t = getLocalizations(context);
        await showCopyableErrorDialog(
          context,
          title: t.dlg_copy_error_title,
          message: t.dlg_play_failed_prefix('$e'),
        );
        return NoMediaActionResult.failed;
      }
    } catch (e) {
      if (!context.mounted) return NoMediaActionResult.failed;
      final t = getLocalizations(context);
      final message = e is PlaybackUnavailableException
          ? e.displayMessage(t)
          : t.dlg_play_failed_prefix('$e');
      await showCopyableErrorDialog(
        context,
        title: t.dlg_copy_error_title,
        message: message,
      );
      return NoMediaActionResult.failed;
    }
  }
}

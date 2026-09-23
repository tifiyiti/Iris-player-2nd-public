import 'package:iris/l10n/app_localizations.dart';

/// Domain error thrown by play actions when nothing can actually be played
/// (v15-D6): the prospective scope is empty or every item is unavailable. The
/// throwing action MUST NOT have mutated the workspace — the caller keeps the
/// player untouched and surfaces the localized text via `showCopyableErrorDialog`.
///
/// [message] carries the error CODE for known cases (e.g.
/// `search_err_no_results`) or the raw display text for ad-hoc cases; use
/// [displayMessage] at the UI boundary to resolve it.
class PlaybackUnavailableException implements Exception {
  /// Either an l10n error code or raw display text (v15-D6).
  final String message;

  /// Optional parameter for parameterized codes (e.g. folder path for
  /// `search_err_empty_folder`).
  final String? param;

  const PlaybackUnavailableException(this.message, [this.param]);

  /// Parameterized empty-folder case.
  const PlaybackUnavailableException.emptyFolder(String folder)
      : message = 'search_err_empty_folder',
        param = folder;

  /// Resolves the user-displayable, copyable reason (v15-D6).
  String displayMessage(AppLocalizations t) {
    switch (message) {
      case 'search_err_no_results':
        return t.search_err_no_results;
      case 'search_err_scenario_missing':
        return t.search_err_scenario_missing;
      case 'search_err_selection_not_in_db':
        return t.search_err_selection_not_in_db;
      case 'search_err_empty_folder':
        return t.search_err_empty_folder(param ?? '/');
      default:
        return message;
    }
  }

  @override
  String toString() => message;
}

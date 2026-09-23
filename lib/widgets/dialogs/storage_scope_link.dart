import 'package:flutter/material.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_scope_key.dart';
import 'package:iris/utils/get_localizations.dart';

/// Confirms sharing an existing media library when [candidate] matches an
/// existing entry's account + path tree, and returns the storage to persist.
///
/// Add mode ([isEdit] false, default):
///  * no match → the candidate with its scope cleared;
///  * match confirmed → the candidate linked to the matched scope;
///  * cancelled → `null` — the caller aborts the save (a new entry that
///    duplicates an existing tree must never start an independent library).
///
/// Edit mode ([isEdit] true, [originalScopeId] = the entry's current scope):
/// the prompt is shown ONLY when the edit moves the entry into a DIFFERENT
/// scope; staying in (or matching nothing beyond) the original scope — which
/// includes the owner's own linked siblings resolving back to it — silently
/// keeps it, and cancelling keeps [originalScopeId] instead of discarding the
/// edit. A path change that breaks the relation clears the scope (the entry is
/// no longer the same tree).
Future<Storage?> resolveSharedLibraryLink(
  BuildContext context,
  Storage candidate,
  Iterable<Storage> existing, {
  bool isEdit = false,
  String? originalScopeId,
}) async {
  final match = findSharedScope(candidate, existing);
  final currentScope = originalScopeId ?? candidate.id;

  if (match == null) {
    // No same-tree sibling. Add stays independent; an edit that broke the
    // relation becomes independent too (see doc above).
    return _withScope(candidate, null);
  }

  // Same scope the entry already belongs to (including the owner's own
  // siblings resolving back to it) → keep silently, no prompt.
  if (isEdit && match.scopeId == currentScope) {
    return _withScope(candidate, originalScopeId);
  }

  final t = getLocalizations(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.storage_shared_library_title),
      content: Text(t.storage_shared_library_message(match.storage.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t.ok),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    // Add: abort. Edit: keep the original link, never lose the edit.
    return isEdit ? _withScope(candidate, originalScopeId) : null;
  }
  return _withScope(candidate, match.scopeId);
}

Storage _withScope(Storage storage, String? scopeId) => storage.map(
      local: (s) => s.copyWith(dataScopeId: scopeId),
      webdav: (s) => s.copyWith(dataScopeId: scopeId),
      ftp: (s) => s.copyWith(dataScopeId: scopeId),
    );

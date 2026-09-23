import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:iris/features/meta_settings/meta_settings_module.dart';

/// Ordered building blocks of a composed storage name.
enum StorageNameTag {
  type('type'),
  account('account'),
  host('host'),
  port('port'),
  path('path');

  const StorageNameTag(this.id);

  /// Stable token used in the AUX row encoding (never localized).
  final String id;

  static StorageNameTag? tryParse(String? id) {
    if (id == null) return null;
    final token = id.trim();
    for (final tag in StorageNameTag.values) {
      if (tag.id == token) return tag;
    }
    return null;
  }
}

/// Persisted storage-name template value.
class StorageNameTemplate {
  const StorageNameTemplate({
    this.tags = defaultTags,
    this.separator = defaultSeparator,
    this.enabled = true,
  });

  static const List<StorageNameTag> defaultTags = <StorageNameTag>[
    StorageNameTag.type,
    StorageNameTag.account,
  ];
  static const String defaultSeparator = '·';

  /// Ordered tag list; the order is the composition order.
  final List<StorageNameTag> tags;
  final String separator;

  /// When true, template edits are written globally the moment they happen;
  /// when false they are session-local (the DB keeps the last saved value).
  final bool enabled;

  StorageNameTemplate copyWith({
    List<StorageNameTag>? tags,
    String? separator,
    bool? enabled,
  }) =>
      StorageNameTemplate(
        tags: tags ?? this.tags,
        separator: separator ?? this.separator,
        enabled: enabled ?? this.enabled,
      );
}

/// AUX-row backed storage-name template preferences.
///
/// `storage.name*` rows live OUTSIDE the `app.%` wipe scope (same contract as
/// `virtualmedia.*`), so they survive settings snapshots. Gate-OFF runs degrade
/// to the code defaults and the template UI is absent.
abstract final class StorageNamePrefs {
  static const String prefix = 'storage.';
  static const String tagsKey = '${prefix}nameTags';
  static const String separatorKey = '${prefix}nameSeparator';
  static const String enabledKey = '${prefix}nameTemplateEnabled';

  /// Maximum accepted separator length — keeps the composed name readable.
  static const int maxSeparatorLength = 9;

  static StorageNameTemplate _snapshot = const StorageNameTemplate();

  /// In-session template, seeded by [load] at startup. Read synchronously by
  /// the dialogs so the cached form stays pure (no async rebuild).
  static StorageNameTemplate get template => _snapshot;

  /// Loads the persisted template into the in-memory snapshot. Fail-soft: a
  /// missing module or read error degrades to the code defaults.
  static Future<void> load() async {
    if (!MetaSettingsModule.ready) {
      _snapshot = const StorageNameTemplate();
      return;
    }
    try {
      final rows = await MetaSettingsModule.repo.loadRawValues();
      _snapshot = _parse(rows);
    } catch (_) {
      _snapshot = const StorageNameTemplate();
    }
  }

  static StorageNameTemplate _parse(Map<String, String> rows) {
    final rawTags = rows[tagsKey];
    final tags = <StorageNameTag>[];
    if (rawTags != null) {
      for (final token in rawTags.split(',')) {
        final tag = StorageNameTag.tryParse(token);
        if (tag != null && !tags.contains(tag)) tags.add(tag);
      }
    }
    final rawSeparator = rows[separatorKey];
    final separator = rawSeparator == null
        ? StorageNameTemplate.defaultSeparator
        : _clampSeparator(rawSeparator);
    return StorageNameTemplate(
      tags: rawTags == null ? StorageNameTemplate.defaultTags : tags,
      separator: separator,
      enabled: rows[enabledKey] != '0',
    );
  }

  static String _clampSeparator(String value) =>
      value.length > maxSeparatorLength
          ? value.substring(0, maxSeparatorLength)
          : value;

  static String _encodeTags(List<StorageNameTag> tags) =>
      tags.map((tag) => tag.id).join(',');

  /// Records a new tag order in-session and, when the template is global,
  /// persists it.
  static void updateTags(List<StorageNameTag> tags) {
    _snapshot = _snapshot.copyWith(tags: List<StorageNameTag>.unmodifiable(tags));
    if (_snapshot.enabled) {
      unawaited(MetaSettingsModule.persistAuxRow(tagsKey, _encodeTags(tags)));
    }
  }

  /// Records a new separator in-session WITHOUT touching storage.
  ///
  /// The separator field commits via [commitSeparator] on blur/submit: Drift
  /// runs on the UI isolate (`NativeDatabase`), so persisting on every
  /// keystroke would block the frame while the user types.
  static void applySeparator(String separator) {
    _snapshot = _snapshot.copyWith(separator: _clampSeparator(separator));
  }

  /// Flushes the in-session separator (applied via [applySeparator]) to storage
  /// when the template is global.
  static void commitSeparator() {
    if (_snapshot.enabled) {
      unawaited(
          MetaSettingsModule.persistAuxRow(separatorKey, _snapshot.separator));
    }
  }

  /// Records and immediately persists a separator. Kept for callers that commit
  /// atomically (e.g. tests); the dialog uses [applySeparator]/[commitSeparator].
  static void updateSeparator(String separator) {
    applySeparator(separator);
    commitSeparator();
  }

  /// Toggles global persistence. Turning it on promotes the current session
  /// draft (tags + separator) so "make it global" does what it says.
  static void updateEnabled(bool enabled) {
    _snapshot = _snapshot.copyWith(enabled: enabled);
    unawaited(MetaSettingsModule.persistAuxRow(enabledKey, enabled ? '1' : '0'));
    if (enabled) {
      unawaited(MetaSettingsModule.persistAuxRow(tagsKey, _encodeTags(_snapshot.tags)));
      unawaited(MetaSettingsModule.persistAuxRow(separatorKey, _snapshot.separator));
    }
  }

  /// Restores the true defaults (`type` + `account`, separator `·`); persists
  /// when the template is global. The global flag itself is left untouched.
  static void reset() {
    _snapshot = _snapshot.copyWith(
      tags: StorageNameTemplate.defaultTags,
      separator: StorageNameTemplate.defaultSeparator,
    );
    if (_snapshot.enabled) {
      unawaited(MetaSettingsModule.persistAuxRow(
          tagsKey, _encodeTags(StorageNameTemplate.defaultTags)));
      unawaited(MetaSettingsModule.persistAuxRow(
          separatorKey, StorageNameTemplate.defaultSeparator));
    }
  }

  @visibleForTesting
  static void debugResetSnapshot() {
    _snapshot = const StorageNameTemplate();
  }
}

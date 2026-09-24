import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/services/background_candidate_cache.dart';
import 'package:iris/features/background_playback/store/bg_source_bootstrap.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

/// Repository-level contract for the built-in 副音 source rule, plus the
/// "rules changed outside the playing panel" invalidation signal.
void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() => db.close());

  setUp(() async {
    for (final r in await DbModule.bgSourceRuleRepo.loadRules()) {
      await DbModule.bgSourceRuleRepo.deleteRule(r.id);
    }
  });

  group('built-in rule write guard (mirror of the delete guard)', () {
    test('seeding a NEW built-in row still upserts', () async {
      final seeded = BgSourceBootstrap.builtinRule();
      await DbModule.bgSourceRuleRepo.saveRule(seeded);

      final loaded = await DbModule.bgSourceRuleRepo.ruleById(seeded.id);
      expect(loaded, isNotNull);
      expect(loaded!.builtin, isTrue);
      expect(loaded.kind, BgSourceRuleKind.tag);
      expect(loaded.enabled, isTrue);
      expect(loaded.pinned, isTrue);
    });

    test('an EXISTING built-in row keeps its definition on save', () async {
      final seeded = BgSourceBootstrap.builtinRule();
      await DbModule.bgSourceRuleRepo.saveRule(seeded);

      // A staged manager could hand back a hand-edited built-in definition;
      // saveRule must refuse the definition change while still honoring the
      // enable/pin flags (the only mutations the UI offers for built-ins).
      await DbModule.bgSourceRuleRepo.saveRule(
        seeded.copyWith(
          name: 'tampered',
          kind: BgSourceRuleKind.directory,
          enabled: false,
          pinned: false,
        ),
      );

      final loaded = await DbModule.bgSourceRuleRepo.ruleById(seeded.id);
      expect(loaded!.name, isNot('tampered'), reason: 'definition is protected');
      expect(loaded.kind, BgSourceRuleKind.tag, reason: 'kind is protected');
      expect(loaded.enabled, isFalse, reason: 'enable is still plumbed');
      expect(loaded.pinned, isFalse, reason: 'pin is still plumbed');
    });

    test('a non-built-in rule saves freely', () async {
      const id = 'bgsrc_plain';
      await DbModule.bgSourceRuleRepo
          .saveRule(const BgSourceRule(id: id, name: 'first'));
      await DbModule.bgSourceRuleRepo
          .saveRule(const BgSourceRule(id: id, name: 'second'));

      final loaded = await DbModule.bgSourceRuleRepo.ruleById(id);
      expect(loaded!.name, 'second');
    });
  });

  group('invalidateSourceRules', () {
    test('drops the session pool without throwing when idle', () async {
      // The gate is off in the test environment, so the helper is a no-op —
      // it must never throw on the confirm path.
      expect(BackgroundPlaybackActions.invalidateSourceRules, returnsNormally);
    });

    test('BackgroundCandidateCache.invalidate clears the cached pool', () {
      final cache = BackgroundCandidateCache(
        ruleRepo: DbModule.bgSourceRuleRepo,
      );
      expect(cache.invalidate, returnsNormally);
    });

    test('a resolution-relevant rule edit re-resolves WITHOUT invalidate',
        () async {
      // Corrected understanding (supersedes the H1 hypothesis): the cache keys
      // on a rule fingerprint covering id/enabled/kind/pinned/paths/..., so a
      // staged-manager edit is picked up on the next read by itself. This test
      // pins that contract so an explicit invalidate is not needed for it.
      final cache = BackgroundCandidateCache(
        ruleRepo: DbModule.bgSourceRuleRepo,
        dedupeOf: () async => false,
      );

      final first = await cache.pool();

      // A rule write (as confirm() does) changes the fingerprint.
      await DbModule.bgSourceRuleRepo.saveRule(const BgSourceRule(
        id: 'bgsrc_cache_probe',
        name: 'probe',
        kind: BgSourceRuleKind.tag,
        enabled: false,
      ));
      final afterEdit = await cache.pool();
      expect(identical(first, afterEdit), isFalse,
          reason: 'a fingerprint-relevant write re-resolves on its own');

      // invalidate() also forces it, harmlessly (idempotent safety net).
      cache.invalidate();
      final afterInvalidate = await cache.pool();
      expect(identical(afterEdit, afterInvalidate), isFalse);

      await DbModule.bgSourceRuleRepo.deleteRule('bgsrc_cache_probe');
    });
  });
}

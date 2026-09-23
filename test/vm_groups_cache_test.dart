import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/resolver/vm_stream_merge.dart';

/// Play/next/prev/completion must not re-resolve the whole stream every tap:
/// groups are cached per effective-stream signature and refreshed only when
/// the signature moves or the tapped entry is missing (stale content).
void main() {
  group('vmGroupsCacheAction', () {
    test('fresh resolve when nothing cached', () {
      expect(
        vmGroupsCacheAction(
          cachedSignature: null,
          currentSignature: 's|a',
          entryCoveredInCache: false,
        ),
        VmGroupsCacheAction.resolveFresh,
      );
    });

    test('cached groups reused when signature matches and entry covered', () {
      expect(
        vmGroupsCacheAction(
          cachedSignature: 's|a',
          currentSignature: 's|a',
          entryCoveredInCache: true,
        ),
        VmGroupsCacheAction.useCached,
      );
    });

    test('signature move (sort/shuffle/rule edit) forces fresh resolve', () {
      expect(
        vmGroupsCacheAction(
          cachedSignature: 's|a',
          currentSignature: 's|b',
          entryCoveredInCache: true,
        ),
        VmGroupsCacheAction.resolveFresh,
      );
    });

    test('covered-but-missing entry means stale content: refresh once', () {
      // coveringRuleFor already said a rule covers the entry, yet neither
      // byKey nor failByKey knows it (e.g. a file scanned after caching).
      expect(
        vmGroupsCacheAction(
          cachedSignature: 's|a',
          currentSignature: 's|a',
          entryCoveredInCache: false,
        ),
        VmGroupsCacheAction.resolveFresh,
      );
    });
  });
}

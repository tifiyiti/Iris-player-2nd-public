import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/persistent_store.dart';

class _TestStore extends PersistentStore<List<String>> {
  _TestStore({required this.throwOnLoad}) : super(const <String>[]);

  final bool throwOnLoad;
  int loadCalls = 0;
  int saveCalls = 0;
  List<String>? lastSaved;

  @override
  Future<List<String>?> load() async {
    loadCalls++;
    if (throwOnLoad) throw StateError('backend unavailable');
    return const <String>['loaded'];
  }

  @override
  Future<void> save(List<String> state) async {
    saveCalls++;
    lastSaved = state;
  }
}

/// Durability contract: a store whose load FAILED holds its default state, so
/// persisting it would overwrite good data with nothing. Writes must be off.
void main() {
  test('a failed load marks the store not-ok and blocks writes', () async {
    final store = _TestStore(throwOnLoad: true);
    await store.initialized;

    expect(store.loadOk, isFalse);
    expect(store.state, isEmpty);

    await store.dispose();
    expect(store.saveCalls, 0,
        reason: 'dispose must never persist a store that never loaded');
  });

  test('a successful load marks the store ok and writes normally', () async {
    final store = _TestStore(throwOnLoad: false);
    await store.initialized;

    expect(store.loadOk, isTrue);
    expect(store.state, const <String>['loaded']);

    await store.dispose();
    expect(store.saveCalls, 1);
    expect(store.lastSaved, const <String>['loaded']);
  });
}

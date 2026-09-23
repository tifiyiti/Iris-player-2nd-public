import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/popups/storages/db/storages_db_list.dart';

// The Storage-tab storage tile's primary trailing button is the recursive scan
// in scenario mode; the whole-storage Play moved into the more menu, so the
// scenario menu no longer carries a scan entry. The legacy shape keeps its
// Edit/Remove menu (plus the scan entry, disabled offline).
void main() {
  test('scenario menu is Play Override + Play Append + Edit + Remove', () {
    final actions = storageTileMenuActions(
      scenarioMode: true,
      canScan: true,
      online: true,
      isScanned: false,
    );
    expect(actions.map((a) => a.action), <StorageTileAction>[
      StorageTileAction.play,
      StorageTileAction.playAppend,
      StorageTileAction.edit,
      StorageTileAction.remove,
    ]);
  });

  test('scenario scan is not a menu entry (it is the primary button)', () {
    final actions = storageTileMenuActions(
      scenarioMode: true,
      canScan: true,
      online: true,
      isScanned: false,
    );
    expect(actions.any((a) => a.action == StorageTileAction.scan), isFalse);
  });

  test('scenario scanned storage keeps the play entries only', () {
    final actions = storageTileMenuActions(
      scenarioMode: true,
      canScan: true,
      online: true,
      isScanned: true,
    );
    expect(actions.map((a) => a.action), <StorageTileAction>[
      StorageTileAction.play,
      StorageTileAction.playAppend,
    ]);
  });

  test('legacy shape keeps edit/remove and adds scan when canScan', () {
    final actions = storageTileMenuActions(
      scenarioMode: false,
      canScan: true,
      online: true,
      isScanned: false,
    );
    expect(actions.map((a) => a.action),
        containsAll(<StorageTileAction>[
      StorageTileAction.scan,
      StorageTileAction.edit,
      StorageTileAction.remove,
    ]));
  });

  test('legacy scan is disabled offline', () {
    final actions = storageTileMenuActions(
      scenarioMode: false,
      canScan: true,
      online: false,
      isScanned: false,
    );
    final scan =
        actions.where((a) => a.action == StorageTileAction.scan).toList();
    expect(scan, hasLength(1));
    expect(scan.single.enabled, isFalse);
  });

  test('legacy scanned local storage has no menu', () {
    final actions = storageTileMenuActions(
      scenarioMode: false,
      canScan: true,
      online: true,
      isScanned: true,
    );
    expect(actions, isEmpty);
  });

  test('scan is absent when the non-legacy stack is off', () {
    final actions = storageTileMenuActions(
      scenarioMode: false,
      canScan: false,
      online: true,
      isScanned: false,
    );
    expect(actions.any((a) => a.action == StorageTileAction.scan), isFalse);
  });
}

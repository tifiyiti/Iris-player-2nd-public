import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/probe/media_probe.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_preflight.dart';
import 'package:iris/features/virtual_media/service/vm_duration_scan.dart';
import 'package:iris/features/virtual_media/service/vm_overlay_service.dart';
import 'package:iris/models/storages/storage.dart';

VirtualSegment seg(String name) {
  return VirtualSegment(
    mediaKey: 'st1:Shorts/$name',
    storageId: 'st1',
    path: ['Shorts', name],
    name: name,
    parentPath: 'Shorts',
  );
}

class CountingProbe implements MediaProbeService {
  int fileCalls = 0;

  @override
  Future<ProbeResult> probeFile(String target) async {
    fileCalls++;
    return const ProbeResult(durationMs: 60000);
  }

  @override
  Future<List<ProbeResult>> probeFiles(List<String> targets) async {
    fileCalls += targets.length;
    return List.filled(targets.length, const ProbeResult(durationMs: 60000));
  }
}

Future<bool> noopWriteBack({
  required String storageId,
  required String path,
  int? durationMs,
  int? width,
  int? height,
}) async =>
    true;

void main() {
  test('skipKeys fail fast without touching the probe service', () async {
    final probe = CountingProbe();
    final outcome = await scanVmGroupDurations(
      [seg('known-empty.mp4'), seg('fresh.mp4')],
      probeService: probe,
      writeBack: noopWriteBack,
      storageTypeOf: (_) => StorageType.internal,
      skipKeys: {'st1:Shorts/known-empty.mp4'},
    );
    expect(probe.fileCalls, 1);
    expect(outcome.failedKeys, ['st1:Shorts/known-empty.mp4']);
    expect(outcome.succeededKeys, ['st1:Shorts/fresh.mp4']);
  });

  test('shellUnsupported cache marks, queries and clears on invalidate', () {
    final service = VirtualMediaService.instance;
    addTearDown(service.invalidate);
    expect(service.isShellUnsupported('k1'), isFalse);
    service.markShellUnsupported(['k1', 'k2']);
    expect(service.isShellUnsupported('k1'), isTrue);
    expect(service.isShellUnsupported('k2'), isTrue);
    expect(service.isShellUnsupported('k3'), isFalse);
    service.invalidate();
    expect(service.isShellUnsupported('k1'), isFalse);
  });

  test('failFingerprint is stable for same content, changes on change', () {
    final service = VirtualMediaService.instance;
    addTearDown(service.invalidate);
    final empty = service.failFingerprint;
    service.markShellUnsupported(['x']);
    // Shell-support bookkeeping must not affect the fail fingerprint.
    expect(service.failFingerprint, empty);
    const info = VmFailInfo(
      reason: VmFailReason.zeroDuration,
      detail: 'd',
      scopeKey: 's',
      ruleId: 'r',
    );
    service.setLastFail({'k1': info}, failedGroups: const []);
    final one = service.failFingerprint;
    expect(one, isNot(empty));
    // Same content re-published (a re-resolve) keeps the fingerprint so
    // list subscribers do not self-trigger.
    service.setLastFail({'k1': info}, failedGroups: const []);
    expect(service.failFingerprint, one);
    service.setLastFail({'k1': info, 'k2': info}, failedGroups: const []);
    expect(service.failFingerprint, isNot(one));
  });
}

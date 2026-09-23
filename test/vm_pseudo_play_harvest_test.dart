import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/service/vm_pseudo_play_harvest.dart';
import 'package:iris/l10n/app_localizations_zh.dart';

VirtualSegment hseg(String name) {
  return VirtualSegment(
    mediaKey: 'st1:Shorts/$name',
    storageId: 'st1',
    path: ['Shorts', name],
    name: name,
    parentPath: 'Shorts',
  );
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
  test('harvest writes usable durations and only touches given segments',
      () async {
    final opened = <String>[];
    final written = <String>[];
    final outcome = await harvestVmDurations(
      [hseg('1.mp4'), hseg('2.mp4')],
      opener: (seg) async {
        opened.add(seg.mediaKey);
        return (durationMs: 60000, width: 1280, height: 720);
      },
      writeBack: ({
        required String storageId,
        required String path,
        int? durationMs,
        int? width,
        int? height,
      }) async {
        written.add('$storageId:$path');
        return true;
      },
    );
    expect(outcome.ok, isTrue);
    expect(outcome.scanned, 2);
    expect(opened, ['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4']);
    expect(written, ['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4']);
    expect(outcome.summary(AppLocalizationsZh()), contains('成功2'));
  });

  test('null opener result and throw both degrade to failures, never throw',
      () async {
    final outcome = await harvestVmDurations(
      [hseg('1.mp4'), hseg('bad.mp4')],
      opener: (seg) async {
        if (seg.name == 'bad.mp4') throw StateError('open failed');
        return null;
      },
      writeBack: noopWriteBack,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.failedKeys,
        ['st1:Shorts/1.mp4', 'st1:Shorts/bad.mp4']);
  });

  test('hanging opener hits per-file timeout and continues', () async {
    final outcome = await harvestVmDurations(
      [hseg('slow.mp4'), hseg('fast.mp4')],
      opener: (seg) async {
        if (seg.name == 'slow.mp4') {
          await Future<void>.delayed(const Duration(seconds: 30));
          return (durationMs: 1, width: null, height: null);
        }
        return (durationMs: 5000, width: null, height: null);
      },
      writeBack: noopWriteBack,
      perFileTimeout: const Duration(milliseconds: 100),
    );
    expect(outcome.ok, isFalse);
    expect(outcome.failedKeys, ['st1:Shorts/slow.mp4']);
    expect(outcome.succeededKeys, ['st1:Shorts/fast.mp4']);
  });

  test('cancel stops after current file and keeps partial results', () async {
    var calls = 0;
    final outcome = await harvestVmDurations(
      [hseg('1.mp4'), hseg('2.mp4'), hseg('3.mp4')],
      opener: (seg) async => (durationMs: 1000, width: null, height: null),
      writeBack: noopWriteBack,
      shouldCancel: () => calls++ >= 1,
    );
    expect(outcome.cancelled, isTrue);
    expect(outcome.succeededKeys, hasLength(1));
  });

  test('non-positive duration is a failure even when opener returns a record',
      () async {
    final outcome = await harvestVmDurations(
      [hseg('zero.mp4')],
      opener: (seg) async => (durationMs: 0, width: 1280, height: 720),
      writeBack: noopWriteBack,
    );
    expect(outcome.ok, isFalse);
    expect(outcome.scanned, 0);
  });

  test('budget expiry reports timedOut, not user-cancelled', () async {
    final outcome = await harvestVmDurations(
      [hseg('1.mp4'), hseg('2.mp4')],
      opener: (seg) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return (durationMs: 1000, width: null, height: null);
      },
      writeBack: noopWriteBack,
      perFileTimeout: const Duration(seconds: 10),
      totalBudget: const Duration(milliseconds: 50),
    );
    expect(outcome.timedOut, isTrue);
    expect(outcome.cancelled, isFalse);
  });

  test('late result of a timed-out file never attributes to the next file',
      () async {
    final written = <String, int>{};
    final outcome = await harvestVmDurations(
      [hseg('slow.mp4'), hseg('fast.mp4')],
      opener: (seg) async {
        if (seg.name == 'slow.mp4') {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return (durationMs: 111, width: null, height: null);
        }
        return (durationMs: 222, width: null, height: null);
      },
      writeBack: ({
        required String storageId,
        required String path,
        int? durationMs,
        int? width,
        int? height,
      }) async {
        written[path] = durationMs ?? 0;
        return true;
      },
      perFileTimeout: const Duration(milliseconds: 100),
    );
    expect(outcome.failedKeys, ['st1:Shorts/slow.mp4']);
    expect(outcome.succeededKeys, ['st1:Shorts/fast.mp4']);
    expect(written['Shorts/fast.mp4'], 222);
    expect(written.containsKey('Shorts/slow.mp4'), isFalse);
  });
}

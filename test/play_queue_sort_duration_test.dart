import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/play_queue/data_source/paged_play_queue_data_source.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/path_conv.dart';

/// Play-queue "by duration" sort (Ctrl+7 / `playq_sort_duration`).
///
/// Regression: `_durationOf` and `_dateOf` were byte-identical (both read
/// `lastModified`), so "by duration" silently equalled "by date". These tests
/// pin the duration axis to the real `FileItem.durationMs` and prove it
/// diverges from the date axis.
FileItem _file(
  String name, {
  int? durationMs,
  DateTime? modified,
  String storageId = 's1',
}) =>
    FileItem(
      storageId: storageId,
      name: name,
      uri: 'file:///dir/$name',
      path: ['dir', name],
      durationMs: durationMs,
      lastModified: modified,
    );

PlayQueueItem _item(
  String name, {
  int? durationMs,
  DateTime? modified,
  int index = 0,
}) =>
    PlayQueueItem(
      file: _file(name, durationMs: durationMs, modified: modified),
      index: index,
    );

String _key(String name) => canonicalKey('s1', 'dir/$name');

List<String> _names(List<PlayQueueItem> items) =>
    items.map((e) => e.file.name).toList();

void main() {
  test('duration sort diverges from the date (lastModified) sort', () {
    final a = _item('a.mp4',
        durationMs: 3000, modified: DateTime(2024, 1, 1), index: 0);
    final b = _item('b.mp4',
        durationMs: 1000, modified: DateTime(2024, 1, 2), index: 1);
    final c = _item('c.mp4',
        durationMs: 2000, modified: DateTime(2024, 1, 3), index: 2);

    final byDuration = _names(sortPlayQueueByDuration([a, b, c]));
    final byDate = _names(
      [...[a, b, c]]
        ..sort((x, y) => x.file.lastModified!.compareTo(y.file.lastModified!)),
    );

    expect(byDuration, ['b.mp4', 'c.mp4', 'a.mp4'],
        reason: 'duration ascending: 1000 < 2000 < 3000');
    expect(byDate, ['a.mp4', 'b.mp4', 'c.mp4'],
        reason: 'date ascending: Jan 1 < Jan 2 < Jan 3');
    expect(byDuration, isNot(equals(byDate)),
        reason: 'the two axes must never collapse into the same ordering');
  });

  test('unknown duration counts as 0 and sorts first (ascending)', () {
    final a = _item('a.mp4', durationMs: 5000);
    final unknown = _item('x.mp4');
    final c = _item('c.mp4', durationMs: 1000);

    expect(_names(sortPlayQueueByDuration([a, unknown, c])),
        ['x.mp4', 'c.mp4', 'a.mp4']);
  });

  test('resolveQueueDurations backfills durationMs from the key map', () {
    final a = _item('a.mp4');
    final b = _item('b.mp4');
    final resolved = resolveQueueDurations([a, b], {_key('a.mp4'): 4200});

    expect(resolved[0].file.durationMs, 4200,
        reason: 'a keyed match must fill the missing duration');
    expect(resolved[1].file.durationMs, isNull,
        reason: 'an unkeyed item stays unknown');
  });

  test('resolveQueueDurations never overwrites a known duration', () {
    final a = _item('a.mp4', durationMs: 100);
    final resolved = resolveQueueDurations([a], {_key('a.mp4'): 999});

    expect(resolved.single.file.durationMs, 100);
  });

  test('resolveQueueDurations is a no-op on an empty map', () {
    final items = [_item('a.mp4')];
    expect(resolveQueueDurations(items, const {}), same(items));
  });

  test('backfilled durations then drive the duration sort', () {
    final slow = _item('slow.mp4', index: 0);
    final fast = _item('fast.mp4', index: 1);
    final resolved = resolveQueueDurations(
      [slow, fast],
      {_key('slow.mp4'): 9000, _key('fast.mp4'): 1000},
    );

    expect(_names(sortPlayQueueByDuration(resolved)),
        ['fast.mp4', 'slow.mp4']);
  });
}

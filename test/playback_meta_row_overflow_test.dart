import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/view/widgets/playback_meta_row.dart';
import 'package:iris/l10n/app_localizations.dart';

MediaNode _video({int size = 3 * 1024 * 1024 * 1024, int duration = 0}) =>
    MediaNode.file(
      id: 'st1:Shorts/1.mp4',
      storageId: 'st1',
      path: const ['Shorts', '1.mp4'],
      parentPath: 'Shorts',
      name: '1.mp4',
      mediaType: MediaType.video,
      sizeInBytes: size,
      durationMs: duration,
    );

PlaybackMetaRow _worstCaseMergedRow() => PlaybackMetaRow(
      // Merged totals + both secondary badges + sort date + progress, i.e. the
      // full content set a merged row can carry.
      size: 12 * 1024 * 1024 * 1024,
      durationMs: 12 * 3600 * 1000,
      isMerged: true,
      segmentCount: 12,
      sortValue: '2026-09-19 14:30',
      showProgress: true,
      media: _video(),
      fileDurationMs: 3600 * 1000,
      isCurrent: true,
      duplicated: true,
      occurrenceIndex: 2,
      explicit: true,
    );

Future<void> _pumpInTile(WidgetTester tester, PlaybackMetaRow row) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ListView(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            leading: const Icon(Icons.graphic_eq, size: 16),
            // Mirrors the queue tile trailing: 40px disclosure + 48px menu.
            trailing: const SizedBox(
              width: 88,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [SizedBox(width: 40), SizedBox(width: 48)],
              ),
            ),
            title: const Text('[vm] Shorts · 1/3 · 001-012'),
            subtitle: row,
          ),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('merged meta row never overflows a 320px phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpInTile(tester, _worstCaseMergedRow());

    expect(tester.takeException(), isNull);
  });

  testWidgets('summary line is a single ellipsized Text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpInTile(tester, _worstCaseMergedRow());

    final summary = tester.widget<Text>(find.textContaining('seg'));
    expect(summary.maxLines, 1);
    expect(summary.overflow, TextOverflow.ellipsis);
  });

  testWidgets('secondary badges get their own line when present',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpInTile(tester, _worstCaseMergedRow());

    // Duplicate badge and Added chip are rendered, but below the summary.
    final summaryTop = tester.getTopLeft(find.textContaining('seg')).dy;
    final addedTop = tester.getTopLeft(find.text('Added')).dy;
    expect(addedTop, greaterThan(summaryTop));
  });

  testWidgets('ordinary (non-merged) row still renders its size and duration',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpInTile(
      tester,
      PlaybackMetaRow(
        size: 700 * 1024 * 1024,
        durationMs: 65 * 1000,
        isMerged: false,
        segmentCount: 1,
        showProgress: false,
        media: _video(),
        fileDurationMs: 65 * 1000,
        isCurrent: false,
        duplicated: false,
        occurrenceIndex: 0,
        explicit: false,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('01:05'), findsOneWidget);
  });
}

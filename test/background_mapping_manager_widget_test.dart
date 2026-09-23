import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping_summary.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/view/manager/background_mapping_manager_page.dart';
import 'package:iris/l10n/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

MappingSegment _play(int start, int end) => MappingSegment(
      action: MappingAction.playMedia,
      fgStartMs: start,
      fgEndMs: end,
      bgStorageId: 'local',
      bgPath: 'Anime/B-side.mp4',
      bgStartMs: start,
      bgEndMs: end,
      bgStartN: start / 600000,
      bgEndN: end / 600000,
    );

void main() {
  testWidgets('Level-1 lists available and disabled rows on a 360px phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final summaries = [
      const BackgroundMappingSummary(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segmentCount: 2,
        bgNames: ['B-side.mp4'],
        fgName: 'Episode 01',
      ),
      const BackgroundMappingSummary(
        storageId: 'local',
        path: 'Anime/Ep02.mp4',
        fgName: 'Episode 02',
      ),
    ];

    await tester.pumpWidget(_app(BackgroundMappingListView(
      summaries: summaries,
      loading: false,
      onSelect: (_) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Episode 01'), findsOneWidget);
    expect(find.text('Episode 02'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Level-2 renders the 0-100% overview and segment tiles',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final summary = const BackgroundMappingSummary(
      storageId: 'local',
      path: 'Anime/Ep01.mp4',
      fgTotalMs: 600000,
      segmentCount: 1,
      fgName: 'Episode 01',
    );
    final timeline = BackgroundMappingTimeline(
      storageId: 'local',
      path: 'Anime/Ep01.mp4',
      fgTotalMs: 600000,
      segments: [_play(0, 120000)],
    );

    await tester.pumpWidget(_app(BackgroundMappingDetailView(
      summary: summary,
      timeline: timeline,
      onBack: () {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('mapping_overview_track')), findsOneWidget);
    expect(find.text('B-side.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Level-2 without a foreground duration warns and draws no axis',
      (tester) async {
    final summary = const BackgroundMappingSummary(
      storageId: 'local',
      path: 'Anime/Ep09.mp4',
      fgName: 'No Duration',
    );

    await tester.pumpWidget(_app(BackgroundMappingDetailView(
      summary: summary,
      timeline: const BackgroundMappingTimeline(
        storageId: 'local',
        path: 'Anime/Ep09.mp4',
      ),
      onBack: () {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('No foreground duration'), findsOneWidget);
    expect(find.byKey(const ValueKey('mapping_overview_track')), findsNothing);
  });

  testWidgets('Level-2 dirty draft shows the apply banner and delete action',
      (tester) async {
    final summary = const BackgroundMappingSummary(
      storageId: 'local',
      path: 'Anime/Ep01.mp4',
      fgTotalMs: 600000,
      fgName: 'Episode 01',
    );
    final timeline = BackgroundMappingTimeline(
      storageId: 'local',
      path: 'Anime/Ep01.mp4',
      fgTotalMs: 600000,
      segments: [_play(0, 120000), _play(200000, 300000)],
    );
    MappingSegment? deleted;
    MappingSegment? replaced;
    MappingSegment? edited;

    await tester.pumpWidget(_app(BackgroundMappingDetailView(
      summary: summary,
      timeline: timeline,
      dirty: true,
      onDeleteSegment: (s) => deleted = s,
      onReplaceBg: (s) => replaced = s,
      onEditSegment: (s) => edited = s,
      onApply: () {},
      onDiscard: () {},
      onBack: () {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bg_mapping_manager_staged_banner')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bg_mapping_manager_apply')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bg_mapping_manager_discard')),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    expect(deleted, isNotNull);
    expect(deleted!.fgStartMs, 0);

    await tester.tap(find.byIcon(Icons.swap_horiz_rounded).first);
    await tester.pump();
    expect(replaced, isNotNull);
    expect(replaced!.fgStartMs, 0);

    await tester.tap(find.byIcon(Icons.edit_rounded).first);
    await tester.pump();
    expect(edited, isNotNull);
    expect(edited!.fgStartMs, 0);
  });

  testWidgets('Level-1 marks staged drafts with a badge', (tester) async {
    await tester.pumpWidget(_app(BackgroundMappingListView(
      summaries: const [
        BackgroundMappingSummary(
          storageId: 'local',
          path: 'Anime/Ep01.mp4',
          fgTotalMs: 600000,
          segmentCount: 1,
          fgName: 'Episode 01',
        ),
      ],
      loading: false,
      dirtyKeys: const {'local:Anime/Ep01.mp4'},
      onSelect: (_) {},
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Staged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

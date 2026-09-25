import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/scan/commands/scenario_source_scan_command.dart';

/// Regression: a second "扫描更新源数据" trigger while the first is still in its
/// async preflight window (DB reads, remote connect) must JOIN it, not start a
/// duplicate batch whose own options + summary dialogs would stack.
void main() {
  tearDown(() {
    ScenarioSourceScanCommand.debugRunOverride = null;
  });

  testWidgets('concurrent run joins the in-flight refresh', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    var calls = 0;
    final completer = Completer<bool>();
    ScenarioSourceScanCommand.debugRunOverride = (_, __) {
      calls++;
      return completer.future;
    };

    final first = ScenarioSourceScanCommand.run(context, scenarioId: 's1');
    final second = ScenarioSourceScanCommand.run(context, scenarioId: 's1');

    expect(calls, 1, reason: 'the second trigger must not start a second run');
    expect(identical(first, second), isTrue,
        reason: 'the second trigger must return the in-flight future');

    completer.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  testWidgets('a new run starts after the previous one completes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    var calls = 0;
    ScenarioSourceScanCommand.debugRunOverride = (_, __) async {
      calls++;
      return true;
    };

    await ScenarioSourceScanCommand.run(context, scenarioId: 's1');
    await ScenarioSourceScanCommand.run(context, scenarioId: 's1');

    expect(calls, 2, reason: 'a completed run must not block the next one');
  });
}

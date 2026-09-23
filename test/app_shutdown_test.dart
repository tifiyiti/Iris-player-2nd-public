import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_shutdown.dart';

void main() {
  setUp(AppShutdown.reset);
  tearDown(AppShutdown.reset);

  test('hides, silences, saves, disposes, then destroys the window', () async {
    final order = <String>[];
    AppShutdown.configure(
      destroy: () async => order.add('destroy'),
      hide: () async => order.add('hide'),
    );
    AppShutdown.registerQuiesce(() async => order.add('pause'));
    AppShutdown.registerSave(() async => order.add('save'));
    AppShutdown.registerDisposer(() async => order.add('dispose'));

    await AppShutdown.run();

    // The window must be gone before anything slow runs (perceived close).
    expect(order, ['hide', 'pause', 'save', 'dispose', 'destroy']);
  });

  test('a missing hide hook is skipped without blocking the teardown',
      () async {
    final order = <String>[];
    AppShutdown.configure(destroy: () async => order.add('destroy'));
    AppShutdown.registerSave(() async => order.add('save'));

    await AppShutdown.run();

    expect(order, ['save', 'destroy']);
  });

  test('awaits every registered disposer before destroying', () async {
    var slowDone = false;
    var fastDone = false;
    AppShutdown.configure(destroy: () async {});
    AppShutdown.registerDisposer(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      slowDone = true;
    });
    AppShutdown.registerDisposer(() async => fastDone = true);

    await AppShutdown.run();

    expect(slowDone, isTrue);
    expect(fastDone, isTrue);
  });

  test('repeated close events run the shutdown exactly once', () async {
    var saves = 0;
    var disposals = 0;
    var destroys = 0;
    AppShutdown.configure(destroy: () async => destroys++);
    AppShutdown.registerSave(() async => saves++);
    AppShutdown.registerDisposer(() async => disposals++);

    await Future.wait([AppShutdown.run(), AppShutdown.run()]);
    await AppShutdown.run();

    expect(saves, 1);
    expect(disposals, 1);
    expect(destroys, 1);
  });

  test('a throwing save/disposer never blocks the rest nor the destroy',
      () async {
    final order = <String>[];
    AppShutdown.configure(destroy: () async => order.add('destroy'));
    AppShutdown.registerSave(() async => throw StateError('save boom'));
    AppShutdown.registerDisposer(() async => order.add('d1'));
    AppShutdown.registerDisposer(() async => throw StateError('dispose boom'));
    AppShutdown.registerDisposer(() async => order.add('d2'));

    await AppShutdown.run();

    expect(order, ['d1', 'd2', 'destroy']);
  });

  test('destroys the window even when cleanup hangs past the budget', () async {
    var destroyed = false;
    AppShutdown.configure(
      destroy: () async => destroyed = true,
      timeout: const Duration(milliseconds: 20),
    );
    // Never completes: the window must still be released (otherwise the app
    // can never be closed — the one failure mode preventClose introduces).
    AppShutdown.registerDisposer(() => Completer<void>().future);

    await AppShutdown.run();

    expect(destroyed, isTrue);
  });

  test('unregistered callbacks are not invoked', () async {
    final order = <String>[];
    AppShutdown.configure(destroy: () async => order.add('destroy'));
    final unregister =
        AppShutdown.registerDisposer(() async => order.add('dispose'));
    unregister();

    await AppShutdown.run();

    expect(order, ['destroy']);
  });

  test('a cold start with nothing registered still releases the window',
      () async {
    var destroyed = false;
    AppShutdown.configure(destroy: () async => destroyed = true);

    await AppShutdown.run();

    expect(destroyed, isTrue);
  });

  test('force-exits when the window release never terminates the process',
      () async {
    final forced = Completer<void>();
    AppShutdown.configure(
      destroy: () async {}, // release "succeeds" but the process survives
      forceExit: () async {
        if (!forced.isCompleted) forced.complete();
      },
      forceExitAfter: const Duration(milliseconds: 200),
    );

    await AppShutdown.run();
    expect(forced.isCompleted, isFalse, reason: 'not before the grace period');

    await forced.future.timeout(const Duration(seconds: 2));
  });

  test('force-exits when a teardown step hangs forever', () async {
    final forced = Completer<void>();
    AppShutdown.configure(
      destroy: () => Completer<void>().future, // never releases the window
      forceExit: () async {
        if (!forced.isCompleted) forced.complete();
      },
      forceExitAfter: const Duration(milliseconds: 200),
    );

    // run() itself never returns here — the fallback must fire regardless.
    unawaited(AppShutdown.run());

    await forced.future.timeout(const Duration(seconds: 2));
  });

  test('does not force-exit when no fallback is configured', () async {
    AppShutdown.configure(destroy: () async {});

    await AppShutdown.run();

    // Nothing to assert beyond a clean, hang-free run: a stray timer would
    // fail the test with a pending-timer error.
  });

  test('isActive fences the teardown window and stays latched', () async {
    AppShutdown.configure(destroy: () async {});
    expect(AppShutdown.isActive, isFalse);

    // Observed from inside the shutdown: effects reacting to our own state
    // churn must see the fence.
    var activeDuringRun = false;
    AppShutdown.registerQuiesce(() async {
      activeDuringRun = AppShutdown.isActive;
    });

    await AppShutdown.run();

    expect(activeDuringRun, isTrue, reason: 'fence must hold while running');
    expect(
      AppShutdown.isActive,
      isTrue,
      reason: 'fence stays latched: destroy() only asks the OS to exit, so '
          'the tree outlives it and must never restart playback',
    );
  });
}

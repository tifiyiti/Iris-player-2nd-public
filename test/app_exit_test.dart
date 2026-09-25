import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/app_exit.dart';
import 'package:iris/utils/platform.dart';

void main() {
  setUp(() {
    AppExit.reset();
    debugIsMobilePlatformOverride = null;
  });
  tearDown(() {
    AppExit.reset();
    debugIsMobilePlatformOverride = null;
  });

  test('desktop: saves durably, then closes the window', () async {
    final order = <String>[];
    debugIsMobilePlatformOverride = false;
    AppExit.closeWindow = () async => order.add('closeWindow');
    AppExit.popApp = () async => order.add('popApp');
    AppExit.hardExit = () => order.add('hardExit');

    await AppExit.run(() async => order.add('save'));

    expect(order, ['save', 'closeWindow']);
  });

  test('desktop: a failed save never blocks the exit', () async {
    var closed = false;
    debugIsMobilePlatformOverride = false;
    AppExit.closeWindow = () async => closed = true;

    await AppExit.run(() async => throw StateError('save boom'));

    expect(closed, isTrue);
  });

  test('mobile: pops the activity after saving, without a bare exit', () async {
    final order = <String>[];
    debugIsMobilePlatformOverride = true;
    AppExit.popApp = () async => order.add('popApp');
    AppExit.hardExit = () => order.add('hardExit');
    AppExit.fallbackAfter = const Duration(milliseconds: 15);

    await AppExit.run(() async => order.add('save'));

    // The happy path pops the activity and never arms a bare exit.
    expect(order, ['save', 'popApp']);
  });

  test('mobile: hard-exits only after the fallback grace period', () async {
    var hardExited = false;
    debugIsMobilePlatformOverride = true;
    AppExit.popApp = () async {};
    AppExit.hardExit = () => hardExited = true;
    AppExit.fallbackAfter = const Duration(milliseconds: 15);

    await AppExit.run(null);
    expect(hardExited, isFalse, reason: 'not before the grace period');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(hardExited, isTrue);
  });

  test('a null save callback still exits cleanly', () async {
    var closed = false;
    debugIsMobilePlatformOverride = false;
    AppExit.closeWindow = () async => closed = true;

    await AppExit.run(null);

    expect(closed, isTrue);
  });
}

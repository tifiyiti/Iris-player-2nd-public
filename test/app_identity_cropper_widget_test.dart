import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:iris/features/app_identity/services/app_identity_image.dart';
import 'package:iris/features/app_identity/view/entry_image_cropper.dart';
import 'package:iris/l10n/app_localizations.dart';

Uint8List _makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      image.setPixelRgba(x, y, 200, 100, 50, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _Harness extends HookWidget {
  const _Harness({required this.result, this.initialBytes, this.initialCropRect});

  final ValueNotifier<EntryImageEditResult?> result;
  final Uint8List? initialBytes;
  final ui.Rect? initialCropRect;

  @override
  Widget build(BuildContext context) {
    final opened = useState(false);
    useEffect(() {
      if (opened.value) return null;
      opened.value = true;
      Future.microtask(() async {
        final cropped = await showEntryImageEditor(
          context,
          initialBytes: initialBytes,
          initialCropRect: initialCropRect,
        );
        result.value = cropped;
      });
      return null;
    }, []);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('editor without bytes shows Choose-an-image, not decode error',
      (tester) async {
    final result = ValueNotifier<EntryImageEditResult?>(null);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Harness(result: result)));
    await tester.pumpAndSettle();

    expect(find.text('Crop icon'), findsOneWidget);
    // Pre-pick state must be the neutral prompt — never the error text.
    expect(find.text('Choose an image'), findsOneWidget);
    expect(find.text('Could not decode that image'), findsNothing);
    // Use crop stays disabled until an image is picked.
    final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton, 'Use crop'));
    expect(button.onPressed, isNull);
  });

  testWidgets('editor shows the picked image and crops on confirm',
      (tester) async {
    final result = ValueNotifier<EntryImageEditResult?>(null);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Harness(result: result, initialBytes: _makePng(300, 300))));
    await tester.pumpAndSettle();

    // The editor dialog is up; the square frame + "Use crop" button exist.
    expect(find.text('Crop icon'), findsOneWidget);
    expect(find.text('Use crop'), findsOneWidget);

    // Decoding runs on the real engine; poll inside runAsync until the
    // RawImage appears (the useFuture rebuild happens off the fake clock).
    var found = false;
    await tester.runAsync(() async {
      for (int i = 0; i < 50 && !found; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        found = find.byType(RawImage).evaluate().isNotEmpty;
      }
    });
    debugPrint('rawImageAfterPoll=$found '
        'emptyState=${find.text('Choose an image').evaluate().length}');

    // Once decoded, the empty/error texts must NOT appear.
    expect(find.text('Choose an image'), findsNothing);
    expect(find.text('Could not decode that image'), findsNothing);

    // RawImage should be present (decoded image displayed).
    final rawImage = find.byType(RawImage);
    expect(rawImage, findsOneWidget);
    final uiImage = tester.widget<RawImage>(rawImage).image;
    expect(uiImage, isNotNull);
    expect(uiImage!.width, 300);
    expect(uiImage.height, 300);

    // Tap confirm → the dialog pops with the full crop result.
    await tester.tap(find.text('Use crop'));
    await tester.pumpAndSettle();

    expect(find.text('Crop icon'), findsNothing);
    final cropped = result.value;
    expect(cropped, isNotNull);
    // The original source bytes travel back unchanged.
    expect(cropped!.sourceBytes, _makePng(300, 300));
    final decoded = img.decodePng(cropped.png);
    expect(decoded!.width, AppIdentityImage.targetSize);
    expect(decoded.height, AppIdentityImage.targetSize);
    // Full-image crop rect.
    expect(cropped.cropRect.left, closeTo(0, 1e-6));
    expect(cropped.cropRect.top, closeTo(0, 1e-6));
    expect(cropped.cropRect.right, closeTo(1, 1e-6));
    expect(cropped.cropRect.bottom, closeTo(1, 1e-6));
  });

  testWidgets('editing with initialCropRect opens on that region',
      (tester) async {
    final result = ValueNotifier<EntryImageEditResult?>(null);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Harness(
      result: result,
      initialBytes: _makePng(400, 400),
      initialCropRect: const ui.Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
    )));
    await tester.pumpAndSettle();

    var found = false;
    await tester.runAsync(() async {
      for (int i = 0; i < 50 && !found; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        found = find.byType(RawImage).evaluate().isNotEmpty;
      }
    });
    expect(found, isTrue, reason: 'image must decode for the crop test');

    // The initial transform must zoom into the saved rect: frame corners map
    // to normalized [0.25, 0.75] on the source.
    final iv = find.byType(InteractiveViewer);
    final frameSize = tester.getSize(iv).width; // real viewport size
    final controller =
        tester.widget<InteractiveViewer>(iv).transformationController!;
    final rect = visibleCropRect(
      transform: controller.value,
      frameSize: frameSize,
      imageWidth: 400,
      imageHeight: 400,
    );
    expect(rect.left, closeTo(0.25, 0.05));
    expect(rect.right, closeTo(0.75, 0.05));
    expect(rect.top, closeTo(0.25, 0.05));
    expect(rect.bottom, closeTo(0.75, 0.05));
  });
}

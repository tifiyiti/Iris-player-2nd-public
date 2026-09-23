import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iris/features/app_identity/services/app_identity_image.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.appIdentity);

/// Result of a completed crop: the prepared 192×192 icon PNG, the ORIGINAL
/// source bytes (persisted so re-editing can reopen the full image), the
/// source file extension, and the normalized crop rectangle that produced
/// the icon (0..1, relative to the source image).
class EntryImageEditResult {
  const EntryImageEditResult({
    required this.png,
    required this.sourceBytes,
    required this.sourceExtension,
    required this.cropRect,
  });

  /// Prepared icon bytes (square, [AppIdentityImage.targetSize]).
  final Uint8List png;

  /// Original picked image bytes (any decodable format).
  final Uint8List sourceBytes;

  /// Extension of the original file ('' when unknown), used to name the
  /// persisted source copy.
  final String sourceExtension;

  /// Normalized crop rectangle on the source image.
  final ui.Rect cropRect;
}

/// In-app image editor for custom desktop entries.
///
/// Replaces the external uCrop activity (image_cropper), which fails on many
/// Android devices/ROMs. Flow: pick a file via SAF (the system picker copies
/// the chosen file into the app cache — no storage permission needed) →
/// read its bytes → show the image inside a square crop frame with
/// pinch-zoom + pan → confirm returns an [EntryImageEditResult].
///
/// When [initialBytes] + [initialCropRect] are supplied (editing an entry
/// that already has a source image), the view opens on the saved crop
/// region instead of the whole image. Returns null when cancelled.
Future<EntryImageEditResult?> showEntryImageEditor(
  BuildContext context, {
  Uint8List? initialBytes,
  ui.Rect? initialCropRect,
}) async {
  return showDialog<EntryImageEditResult?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EntryImageCropperDialog(
      initialBytes: initialBytes,
      initialCropRect: initialCropRect,
    ),
  );
}

/// Maps the InteractiveViewer transform + square frame onto the source image
/// as a normalized crop rectangle (0..1), used by [AppIdentityImage.cropSquareFromBytes].
///
/// Geometry: the InteractiveViewer child is the image itself at its natural
/// pixel size (`imageWidth × imageHeight`), so child coords == image pixels
/// (`0..W × 0..H`). The crop frame is the viewport (`frameSize × frameSize`).
/// The transform maps child coords → viewport coords as
/// `viewport = scale·child + translate`, so frame corners in image pixels are
/// `(corner - translate) / scale`, clamped to the image bounds.
///
/// Exposed (non-private) so the math is unit-testable.
ui.Rect visibleCropRect({
  required Matrix4 transform,
  required double frameSize,
  required double imageWidth,
  required double imageHeight,
}) {
  final scale = transform.getMaxScaleOnAxis();
  final tx = transform.getTranslation().x;
  final ty = transform.getTranslation().y;

  // Frame corners in image (child) coordinates.
  final imgLeft = 0.0;
  final imgTop = 0.0;
  final imgRight = imageWidth;
  final imgBottom = imageHeight;

  final left = ((0 - tx) / scale).clamp(imgLeft, imgRight).toDouble();
  final top = ((0 - ty) / scale).clamp(imgTop, imgBottom).toDouble();
  final right = ((frameSize - tx) / scale).clamp(imgLeft, imgRight).toDouble();
  final bottom =
      ((frameSize - ty) / scale).clamp(imgTop, imgBottom).toDouble();

  final normLeft = left / imageWidth;
  final normTop = top / imageHeight;
  final normRight = right / imageWidth;
  final normBottom = bottom / imageHeight;

  // Guard degenerate (fully panned away) case: fall back to center square.
  if (normRight <= normLeft || normBottom <= normTop) {
    const c = 0.5;
    const half = 0.4;
    return ui.Rect.fromLTRB(c - half, c - half, c + half, c + half);
  }
  return ui.Rect.fromLTRB(normLeft, normTop, normRight, normBottom);
}

class _EntryImageCropperDialog extends HookWidget {
  const _EntryImageCropperDialog({this.initialBytes, this.initialCropRect});

  final Uint8List? initialBytes;
  final ui.Rect? initialCropRect;

  @override
  Widget build(BuildContext context) {
    final bytes = useState<Uint8List?>(initialBytes);
    final controller = useTransformationController();
    final busy = useState(false);
    // Bytes identity that the current view transform was fitted for. Null
    // until the first fit; reset whenever a NEW image is picked so the fresh
    // image re-fits instead of inheriting the previous pan/zoom (the classic
    // "picked image displays at the wrong size" bug).
    final fittedFor = useRef<Uint8List?>(null);
    // Frame side length, written by the LayoutBuilder (does not rebuild).
    final frameSizeRef = useRef(0.0);
    // Extension of the last picked file, for persisting the source copy.
    final sourceExt = useRef('');

    // Decode the source bytes for display. useFuture rebuilds this widget
    // when decoding completes (replaces manual setState-in-async, which is
    // fragile inside a Dialog route).
    final decodeFuture = useMemoized(
      () => _decodeImage(bytes.value),
      [bytes.value],
    );
    final decode = useFuture(decodeFuture);

    // Fit the freshly decoded image exactly once per source: to the saved
    // crop rect when re-editing, else to the frame (whole image visible).
    useEffect(() {
      final img = decode.data?.image;
      if (img == null) return null;
      if (identical(fittedFor.value, bytes.value)) return null;
      final side = frameSizeRef.value;
      if (side <= 0) {
        // Frame not laid out yet; retry after this frame. The callback
        // guards with context.mounted, so no cancel is needed on dispose.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted &&
              !identical(fittedFor.value, bytes.value) &&
              frameSizeRef.value > 0) {
            _fitToSource(controller, bytes.value, img, frameSizeRef.value,
                initialCropRect);
            fittedFor.value = bytes.value;
          }
        });
        return null;
      }
      _fitToSource(
          controller, bytes.value, img, side, initialCropRect);
      fittedFor.value = bytes.value;
      return null;
    }, [decode.data, controller, bytes.value, initialCropRect]);

    Future<void> pick() async {
      try {
        // image_picker routes through the system photo picker / GET_CONTENT
        // and copies the pick into the app cache — robust across third-party
        // gallery apps and no storage permission required. Returns null on
        // cancel.
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) return; // cancelled
        final data = await File(picked.path).readAsBytes();
        if (data.isEmpty) {
          if (context.mounted) {
            await _errorDialog(
                context, getLocalizations(context).entry_image_file_empty);
          }
          return;
        }
        sourceExt.value = _extensionOf(picked.path);
        bytes.value = data;
      } catch (e) {
        _log.w('image pick failed: $e');
        if (context.mounted) {
          await _errorDialog(
              context, getLocalizations(context).entry_image_pick_failed('$e'));
        }
      }
    }

    Future<void> confirm() async {
      final decoded = decode.data;
      if (decoded == null || busy.value) return;
      busy.value = true;
      try {
        final img = decoded.image;
        // Frame side length from the LayoutBuilder (same formula as above).
        final frameSize = frameSizeRef.value > 0
            ? frameSizeRef.value
            : MediaQuery.sizeOf(context).shortestSide * 0.9;

        final rect = visibleCropRect(
          transform: controller.value,
          frameSize: frameSize,
          imageWidth: img.width.toDouble(),
          imageHeight: img.height.toDouble(),
        );
        final cropped = AppIdentityImage.cropSquareFromBytes(
          decoded.bytes,
          rect: rect,
        );
        if (cropped == null) {
          await _errorDialog(
              context, getLocalizations(context).crop_decode_failed);
          return;
        }
        final source = bytes.value;
        if (source == null) {
          await _errorDialog(
              context, getLocalizations(context).entry_no_source_image);
          return;
        }
        if (context.mounted) {
          Navigator.of(context).pop(EntryImageEditResult(
            png: cropped,
            sourceBytes: source,
            sourceExtension: sourceExt.value,
            cropRect: rect,
          ));
        }
      } finally {
        busy.value = false;
      }
    }

    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      getLocalizations(context).crop_title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: getLocalizations(context).crop_pick_other,
                    onPressed: busy.value ? null : pick,
                    icon: const Icon(Icons.photo_library_outlined),
                  ),
                  IconButton(
                    tooltip: getLocalizations(context).close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = (constraints.biggest.shortestSide * 0.9)
                        .clamp(120.0, 600.0);
                    frameSizeRef.value = side;
                    final img = decode.data?.image;
                    return Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: img == null
                          ? _EmptyState(
                              onPick: pick,
                              failed: decode.hasError,
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: InteractiveViewer(
                                    transformationController: controller,
                                    // The child keeps its NATURAL pixel size so
                                    // child coords == image pixels (the
                                    // visibleCropRect contract). constrained:
                                    // false prevents the viewport from
                                    // stretching the image to the frame.
                                    constrained: false,
                                    minScale: 0.1,
                                    maxScale: 8,
                                    boundaryMargin: const EdgeInsets.all(
                                        double.infinity),
                                    child: SizedBox(
                                      width: img.width.toDouble(),
                                      height: img.height.toDouble(),
                                      child: RawImage(image: img),
                                    ),
                                  ),
                                ),
                                const Positioned.fill(child: _CropOverlay()),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      getLocalizations(context).crop_hint,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: decode.data == null || busy.value
                        ? null
                        : confirm,
                    icon: const Icon(Icons.crop),
                    label: Text(getLocalizations(context).crop_use),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fits the view to the CURRENT [source]: the saved crop rect when this is
  /// the very first source (re-editing), otherwise the whole image.
  void _fitToSource(
    TransformationController controller,
    Uint8List? source,
    ui.Image image,
    double frameSize,
    ui.Rect? initialCropRect,
  ) {
    if (initialCropRect != null && identical(source, initialBytes)) {
      _fitRectToFrame(controller, initialCropRect, frameSize,
          image.width.toDouble(), image.height.toDouble());
    } else {
      _fitToFrame(controller, image, frameSize);
    }
  }
}

/// A decoded image plus the exact byte payload that decoded successfully
/// (the original pick, or a PNG re-encode when the engine rejected the
/// original). `bytes` is what `cropSquareFromBytes` must consume so the
/// crop uses the same interpretation as the preview.
typedef _DecodedImage = ({ui.Image image, Uint8List bytes});

/// Decodes image bytes for display. Returns null when there are no bytes yet
/// (nothing picked — a normal pre-pick state, NOT an error); throws only when
/// the bytes exist but cannot be decoded.
///
/// Falls back to the `image` package codec (broader format support) when the
/// engine codec rejects the payload, re-encoding to PNG so both the engine
/// and the final crop can use it.
Future<_DecodedImage?> _decodeImage(Uint8List? data) async {
  if (data == null) return null;
  try {
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    return (image: frame.image, bytes: data);
  } catch (_) {
    // Engine codec failed (e.g. exotic encoding from a third-party gallery).
    // Try the pure-Dart codec; if it understands the payload, re-encode as
    // PNG and decode that.
    final png = AppIdentityImage.decodeToPng(data);
    if (png == null) rethrow;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    return (image: frame.image, bytes: png);
  }
}

/// Initial transform so the whole image is visible and centered in the
/// square frame (fit-to-frame). The child is the image at its natural pixel
/// size; `viewport = s·child + t` with `t` centering the image in the frame.
void _fitToFrame(
  TransformationController controller,
  ui.Image image,
  double frameSize,
) {
  if (frameSize <= 0 || image.width <= 0 || image.height <= 0) return;
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  final s = (frameSize / w) < (frameSize / h) ? frameSize / w : frameSize / h;
  final tx = (frameSize - s * w) / 2;
  final ty = (frameSize - s * h) / 2;
  final m = Matrix4.identity();
  m.translateByDouble(tx, ty, 0, 1);
  m.scaleByDouble(s, s, s, 1);
  controller.value = m;
}

/// Initial transform that centers the saved [cropRect] region in the frame,
/// scaled so the crop's smaller side fills the frame. Re-approximates the
/// exact view the user cropped with (the frame is square, the crop may not
/// be when it touches an image edge — fit-in keeps it fully visible).
void _fitRectToFrame(
  TransformationController controller,
  ui.Rect rect,
  double frameSize,
  double imageWidth,
  double imageHeight,
) {
  if (frameSize <= 0 || imageWidth <= 0 || imageHeight <= 0) return;
  final left = rect.left.clamp(0.0, 1.0) * imageWidth;
  final top = rect.top.clamp(0.0, 1.0) * imageHeight;
  final right = rect.right.clamp(0.0, 1.0) * imageWidth;
  final bottom = rect.bottom.clamp(0.0, 1.0) * imageHeight;
  final rw = right - left;
  final rh = bottom - top;
  if (rw <= 0 || rh <= 0) return; // keep the default (identity) view
  final side = math.min(rw, rh);
  final scale = frameSize / side;
  final cx = left + rw / 2;
  final cy = top + rh / 2;
  final tx = frameSize / 2 - scale * cx;
  final ty = frameSize / 2 - scale * cy;
  final m = Matrix4.identity();
  m.translateByDouble(tx, ty, 0, 1);
  m.scaleByDouble(scale, scale, scale, 1);
  controller.value = m;
}

String _extensionOf(String path) {
  final idx = path.lastIndexOf('.');
  if (idx < 0 || idx == path.length - 1) return '';
  final ext = path.substring(idx + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
}

class _CropOverlay extends StatelessWidget {
  const _CropOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CropOverlayPainter(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawRect(Offset.zero & size, border);

    // Rule-of-thirds grid.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.35);
    for (int i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick, required this.failed});

  final VoidCallback onPick;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return InkWell(
      onTap: onPick,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            failed
                ? Icons.broken_image_outlined
                : Icons.add_photo_alternate_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(failed ? t.crop_decode_failed : t.crop_choose),
        ],
      ),
    );
  }
}

Future<void> _errorDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(getLocalizations(ctx).entry_title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(getLocalizations(ctx).ok),
        ),
      ],
    ),
  );
}

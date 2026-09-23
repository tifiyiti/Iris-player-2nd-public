import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/store/gesture_region.dart'
    show GestureIntent, GestureLayout, GestureActionType, GestureAction;
import 'package:iris/features/phone/gesture_guide/controller/gesture_guide_presenter.dart'
    show describeAction, guideIntentTitle;
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_controller.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_editor_models.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';

/// Full-screen editor that lets the user:
/// • Drag lines
/// • Tap regions
/// • Assign actions
class GestureEditorOverlay extends HookWidget {
  const GestureEditorOverlay({
    super.key,
    this.profileKey,
    required this.intent,
    required this.initialLayout,
    required this.initialLines,
    required this.allowedActions,
    required this.onSave,
    required this.onCancel,
  });

  final String? profileKey;
  final GestureIntent intent;
  final GestureLayout initialLayout;
  final List<EditableLine> initialLines;
  final List<GestureActionType> allowedActions;

  final void Function(GestureLayout, List<EditableLine>) onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final controller = GestureEditorController();

    final linesState = useState<List<EditableLine>>(
      initialLines.map((l) => EditableLine(axis: l.axis, value: l.value)).toList(),
    );

    final workingLayout = useState<GestureLayout>(
      LayoutTopology(lines: linesState.value).rebuildLayoutFrom(initialLayout, intent),
    );
    final barOffset = useState(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    useEffect(() {
      const margin = Offset(25, 50);
      const barSize = Size(220, 44);

      barOffset.value = Offset(
        screenSize.width - barSize.width - margin.dx,
        screenSize.height - barSize.height - margin.dy,
      );

      return null;
    }, [screenSize]);

    void updateLine(int i, double newValue) {
      final copy = [...linesState.value];
      copy[i].value = controller.clampLineValue(
        line: copy[i],
        all: copy,
        newValue: newValue,
      );

      linesState.value = copy;

      final topology = LayoutTopology(lines: copy);
      workingLayout.value = topology.rebuildLayoutFrom(
        workingLayout.value,
        intent,
      );
    }

    void onRegionTap(int index) async {
      final selected = await showModalBottomSheet<GestureActionType>(
        context: context,
        builder: (sheetCtx) => ListView(
          children: allowedActions.map((a) {
            return ListTile(
              title: Text(describeAction(GestureAction(type: a), t).label),
              trailing: workingLayout.value.regions[index].action.type == a
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, a),
            );
          }).toList(),
        ),
      );

      if (selected != null) {
        final regions = [...workingLayout.value.regions];
        regions[index] = regions[index].copyWith(
          action: GestureAction(type: selected),
        );

        workingLayout.value = workingLayout.value.copyWith(regions: regions);
      }
    }

    Future<void> onResetPressed() async {
      if (!shouldShowWarning(useAppStore().state.suppressedWarnings, kWarningGestureEditReset)) {
        final resetLines =
            initialLines.map((l) => EditableLine(axis: l.axis, value: l.value)).toList();
        linesState.value = resetLines;
        workingLayout.value =
            LayoutTopology(lines: resetLines).rebuildLayoutFrom(initialLayout, intent);
        return;
      }
      final ok = await showConfirmSuppressibleDialog(
        context,
        warningId: kWarningGestureEditReset,
        title: t.gest_reset_title,
        message: t.gest_reset_body,
        confirmLabel: t.gest_reset_confirm,
      );
      if (!ok) return;
      final resetLines =
          initialLines.map((l) => EditableLine(axis: l.axis, value: l.value)).toList();
      linesState.value = resetLines;
      workingLayout.value =
          LayoutTopology(lines: resetLines).rebuildLayoutFrom(initialLayout, intent);
    }

    Future<void> onCancelPressed() async {
      if (!shouldShowWarning(useAppStore().state.suppressedWarnings, kWarningGestureEditCancel)) {
        onCancel();
        return;
      }
      final ok = await showConfirmSuppressibleDialog(
        context,
        warningId: kWarningGestureEditCancel,
        title: t.gest_cancel_title,
        message: t.gest_cancel_body,
        confirmLabel: t.gest_cancel_confirm,
      );
      if (!ok) return;
      onCancel();
    }

    Future<void> onSavePressed() async {
      if (intent == GestureIntent.tap &&
          !tapLayoutHasToggle(workingLayout.value)) {
        await showDialog<void>(
          context: context,
          builder: (_) {
            final t = getLocalizations(context);
            return AlertDialog(
              title: Text(t.gest_keep_toggle_title),
              content: Text(t.gest_keep_toggle_body),
            );
          },
        );
        return;
      }
      if (!shouldShowWarning(useAppStore().state.suppressedWarnings, kWarningGestureEditConfirm)) {
        onSave(workingLayout.value, linesState.value);
        return;
      }
      final ok = await showConfirmSuppressibleDialog(
        context,
        warningId: kWarningGestureEditConfirm,
        title: t.gest_save_title,
        message: t.gest_save_body,
        confirmLabel: t.gest_save_confirm,
      );
      if (!ok) return;
      onSave(workingLayout.value, linesState.value);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await onCancelPressed();
      },
      child: Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final regions = workingLayout.value.regions.map((r) => r.normalizedRect).toList();

          return Stack(
            children: [
              // Regions
              for (int i = 0; i < regions.length; i++)
                Positioned(
                  left: regions[i].left * size.width,
                  top: regions[i].top * size.height,
                  width: regions[i].width * size.width,
                  height: regions[i].height * size.height,
                  child: GestureDetector(
                    onTap: () => onRegionTap(i),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
                      child: Center(
                        child: Text(
                          describeAction(
                                  workingLayout.value.regions[i].action, t)
                              .label,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),

              // Lines
              for (int i = 0; i < linesState.value.length; i++)
                _LineHandle(
                  line: linesState.value[i],
                  screenSize: size,
                  onChanged: (v) => updateLine(i, v),
                ),
              // Floating draggable bar: reset / cancel(arrow_back) / confirm
              Positioned(
                left: barOffset.value.dx,
                top: barOffset.value.dy,
                child: _DraggableEditorBar(
                  title: guideIntentTitle(intent, t),
                  onReset: onResetPressed,
                  onClose: onCancelPressed,
                  onSave: onSavePressed,
                  onDrag: (delta) {
                    final next = barOffset.value + delta;
                    // Bar widened to ~320 for 4 icons
                    barOffset.value = Offset(
                      next.dx.clamp(0, screenSize.width - 320),
                      next.dy.clamp(0, screenSize.height - 44),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _LineHandle extends StatelessWidget {
  const _LineHandle({
    required this.line,
    required this.screenSize,
    required this.onChanged,
  });

  final EditableLine line;
  final Size screenSize;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = (line.value * 100).toStringAsFixed(1);

    return Positioned(
      left: line.axis == LineAxis.vertical ? screenSize.width * line.value - 16 : 0,
      top: line.axis == LineAxis.horizontal ? screenSize.height * line.value - 16 : 0,
      width: line.axis == LineAxis.vertical ? 32 : screenSize.width,
      height: line.axis == LineAxis.horizontal ? 32 : screenSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) {
          final delta = line.axis == LineAxis.vertical
              ? d.delta.dx / screenSize.width
              : d.delta.dy / screenSize.height;

          onChanged(line.value + delta);
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableEditorBar extends StatelessWidget {
  const _DraggableEditorBar({
    required this.title,
    required this.onReset,
    required this.onClose,
    required this.onSave,
    required this.onDrag,
  });

  final String title;
  final VoidCallback onReset;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return GestureDetector(
      onPanUpdate: (d) => onDrag(d.delta),
      child: Material(
        color: const Color(0xFF1E1E2A), // deep bluish gray
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        // borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: t.guide_editor_reset_saved,
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onReset,
              ),
              IconButton(
                // Requirement: leaving the editor is a RETURN to the guide — back arrow instead of X.
                tooltip: t.guide_editor_cancel_back,
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: onClose,
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.drag_indicator, size: 16, color: Colors.white54),
              ),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: t.guide_editor_confirm_save,
                icon: const Icon(Icons.check, size: 18),
                onPressed: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

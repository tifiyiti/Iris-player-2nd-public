import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/store/gesture_region.dart';

enum LineAxis { vertical, horizontal }

class EditableLine {
  EditableLine({
    required this.axis,
    required this.value, // 0..1
    this.minGap = 0.10,
  });

  final LineAxis axis;
  double value;
  final double minGap;
}

class _LineHandle extends StatelessWidget {
  const _LineHandle({
    required this.axis,
    required this.value,
    required this.onChanged,
  });

  final LineAxis axis;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final percent = (value * 100).toStringAsFixed(1);

    return Positioned(
      left: axis == LineAxis.vertical ? size.width * value - 16 : 0,
      top: axis == LineAxis.horizontal ? size.height * value - 16 : 0,
      width: axis == LineAxis.vertical ? 32 : size.width,
      height: axis == LineAxis.horizontal ? 32 : size.height,
      child: GestureDetector(
        onPanUpdate: (d) {
          final delta = axis == LineAxis.vertical ? d.delta.dx / size.width : d.delta.dy / size.height;
          onChanged(value + delta);
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

class _ActionPickerSheet extends StatelessWidget {
  const _ActionPickerSheet({required this.allowed, this.current});

  final List<GestureActionType> allowed;
  final GestureActionType? current;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: allowed.map((a) {
        return ListTile(
          title: Text(a.name),
          trailing: a == current ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, a),
        );
      }).toList(),
    );
  }
}

class GestureRegionEditorOverlay extends HookWidget {
  const GestureRegionEditorOverlay({
    super.key,
    required this.intent,
    required this.initialLayout,
    required this.initialLines,
    required this.allowedActions,
    required this.onSave,
    required this.onCancel,
  });

  final GestureIntent intent;
  final GestureLayout initialLayout;
  final List<EditableLine> initialLines;
  final List<GestureActionType> allowedActions;

  final void Function(GestureLayout layout, List<EditableLine> lines) onSave;
  final VoidCallback onCancel;

  List<Rect> _computeRectRegions(List<EditableLine> lines) {
    final v = lines.where((l) => l.axis == LineAxis.vertical).toList()..sort((a, b) => a.value.compareTo(b.value));
    final h = lines.where((l) => l.axis == LineAxis.horizontal).toList()..sort((a, b) => a.value.compareTo(b.value));

    final xs = [0.0, ...v.map((e) => e.value), 1.0];
    final ys = [0.0, ...h.map((e) => e.value), 1.0];

    final rectRegions = <Rect>[];
    for (int y = 0; y < ys.length - 1; y++) {
      for (int x = 0; x < xs.length - 1; x++) {
        rectRegions.add(Rect.fromLTWH(xs[x], ys[y], xs[x + 1] - xs[x], ys[y + 1] - ys[y]));
      }
    }
    return rectRegions;
  }

  GestureLayout _buildLayout(
    GestureIntent intent,
    List<Rect> rectRegions,
    Map<int, GestureActionType> actions,
  ) {
    return GestureLayout(
      intent: intent,
      regions: List.generate(rectRegions.length, (i) {
        return GestureRegion(
          normalizedRect: rectRegions[i],
          action: GestureAction(type: actions[i] ?? GestureActionType.none),
        );
      }),
    );
  }

  Map<int, GestureActionType> _buildInitialRegionMap(GestureLayout layout) {
    final map = <int, GestureActionType>{};

    for (int i = 0; i < layout.regions.length; i++) {
      map[i] = layout.regions[i].action.type;
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final linesState = useState<List<EditableLine>>(
      initialLines
          .map((l) => EditableLine(
                axis: l.axis,
                value: l.value,
                minGap: l.minGap,
              ))
          .toList(),
    );

    final regionActions = useState<Map<int, GestureActionType>>(
      _buildInitialRegionMap(initialLayout),
    );

    Size screenSize = MediaQuery.sizeOf(context);

    List<Rect> rectRegions = _computeRectRegions(linesState.value);

    void updateLine(int index, double newValue) {
      final lines = [...linesState.value];
      final line = lines[index];

      final sameAxis = lines.where((l) => l.axis == line.axis).toList()..sort((a, b) => a.value.compareTo(b.value));

      final i = sameAxis.indexOf(line);
      final min = i == 0 ? 0.0 : sameAxis[i - 1].value + line.minGap;
      final max = i == sameAxis.length - 1 ? 1.0 : sameAxis[i + 1].value - line.minGap;

      line.value = newValue.clamp(min, max);
      linesState.value = lines;
    }

    void onRegionTap(int index) async {
      final selected = await showModalBottomSheet<GestureActionType>(
        context: context,
        builder: (_) => _ActionPickerSheet(
          allowed: allowedActions,
          current: regionActions.value[index],
        ),
      );

      if (selected != null) {
        regionActions.value = {
          ...regionActions.value,
          index: selected,
        };
      }
    }

    void onSavePressed() {
      final layout = _buildLayout(intent, rectRegions, regionActions.value);
      onSave(layout, linesState.value);
    }

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: Stack(
        children: [
          // Regions
          ...List.generate(rectRegions.length, (i) {
            final r = rectRegions[i];
            return Positioned(
              left: r.left * screenSize.width,
              top: r.top * screenSize.height,
              width: r.width * screenSize.width,
              height: r.height * screenSize.height,
              child: GestureDetector(
                onTap: () => onRegionTap(i),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    color: Colors.transparent,
                  ),
                  child: Center(
                    child: Text(
                      regionActions.value[i]?.name ?? 'none',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
            );
          }),

          // Lines
          ...List.generate(linesState.value.length, (i) {
            final line = linesState.value[i];
            return _LineHandle(
              axis: line.axis,
              value: line.value,
              onChanged: (v) => updateLine(i, v.clamp(0.0, 1.0)),
            );
          }),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: onCancel),
                  const Spacer(),
                  Text(intent.name, style: const TextStyle(color: Colors.white)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.check), onPressed: onSavePressed),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

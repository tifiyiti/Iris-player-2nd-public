import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showSnakeFineWindowDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SnakeFineWindowDialog());

class SnakeFineWindowDialog extends HookWidget {
  const SnakeFineWindowDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final int currentSec = useAppStore().select(context, (state) => state.snakeFineWindowSeconds);
    final int initMin = currentSec ~/ 60;
    final int initSecRem = currentSec % 60;
    final minState = useState<int>(initMin.clamp(0, 10));
    // Seconds are held as absolute seconds; the wheel DOMAIN depends on the
    // minute digit: at 0 minutes only [5..55] exists (5 s floor), otherwise
    // [0..55]. Index mapping: zero-domain i → (i+1)*5, normal i → i*5.
    final secCtrl = useFixedExtentScrollController(
      initialItem: initMin == 0
          ? ((initSecRem - 1) ~/ 5).clamp(0, 10)
          : (initSecRem ~/ 5).clamp(0, 11),
    );
    final secState = useState<int>(
        initMin == 0 ? ((initSecRem - 1) ~/ 5).clamp(0, 10) * 5 + 5 : (initSecRem ~/ 5) * 5);

    int composed() => (minState.value * 60 + secState.value).clamp(5, 600);

    void onMinChanged(int i) {
      final int nv = i.clamp(0, 10);
      final bool wasZero = minState.value == 0;
      minState.value = nv;
      if (nv == 0 && !wasZero) {
        // Entering the 0-minute row: floor the seconds at 5 and re-index.
        if (secState.value < 5) secState.value = 5;
        secCtrl.jumpToItem(((secState.value ~/ 5) - 1).clamp(0, 10));
      } else if (nv != 0 && wasZero) {
        secCtrl.jumpToItem((secState.value ~/ 5).clamp(0, 11));
      }
    }

    void save() {
      useAppStore().updateSnakeFineWindowSeconds(composed());
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(t.snake_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(t.snake_preview(composed()),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(t.snake_minutes),
                    SizedBox(
                      height: 120,
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 32,
                        diameterRatio: 1.2,
                        onSelectedItemChanged: onMinChanged,
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 11,
                          builder: (_, idx) => Center(child: Text('$idx')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(t.snake_seconds),
                    SizedBox(
                      height: 120,
                      child: ListWheelScrollView.useDelegate(
                        controller: secCtrl,
                        itemExtent: 32,
                        diameterRatio: 1.2,
                        onSelectedItemChanged: (i) => secState.value =
                            minState.value == 0 ? (i + 1) * 5 : i * 5,
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: minState.value == 0 ? 11 : 12,
                          builder: (_, idx) => Center(
                            child: Text('${minState.value == 0 ? (idx + 1) * 5 : idx * 5}'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t.snake_hint,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.snake_cancel)),
        FilledButton(onPressed: save, child: Text(t.snake_save)),
      ],
    );
  }
}

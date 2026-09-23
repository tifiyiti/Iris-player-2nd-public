import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/globals.dart' show speedStops, speedSelectorItemWidth;

class SpeedSelector extends HookWidget {
  const SpeedSelector({
    super.key,
    required this.selectedSpeed,
    required this.visualOffset,
    required this.initialSpeed,
  });

  final double selectedSpeed;
  final double visualOffset;
  final double initialSpeed;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    const double itemWidth = speedSelectorItemWidth;
    const double horizontalPadding = 12.0;

    final initialIndex = speedStops.indexOf(initialSpeed);
    final double initialCenterOffset = (screenSize.width / 2) -
        (initialIndex * itemWidth) -
        (itemWidth / 2) -
        horizontalPadding;

    final double targetOffset = initialCenterOffset - visualOffset;

    final double topPosition = screenSize.height / 2 - 30;

    return IgnorePointer(
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            left: targetOffset,
            top: topPosition,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: horizontalPadding),
                  ...speedStops.map((speed) {
                    final bool isSelected = speed == selectedSpeed;
                    return SizedBox(
                      width: itemWidth,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 150),
                          style: TextStyle(
                            fontSize: isSelected ? 20 : 16,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.white70,
                            height: 1.0,
                          ),
                          child: Text('${speed}x'),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: horizontalPadding),
                ],
              ),
            ),
          ),
          Positioned(
            left: screenSize.width / 2 - 1.5,
            top: topPosition - 10,
            child: Container(
              width: 3,
              height: 80,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withAlpha(100),
                      blurRadius: 5,
                    )
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

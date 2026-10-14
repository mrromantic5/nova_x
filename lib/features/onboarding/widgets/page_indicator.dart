// lib/features/onboarding/widgets/page_indicator.dart

import 'package:flutter/material.dart';

class PageIndicator extends StatelessWidget {
  final int count;
  final int current;
  final Color activeColor;

  const PageIndicator({
    super.key,
    required this.count,
    required this.current,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width:  isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(4),
            boxShadow: isActive
                ? [BoxShadow(color: activeColor.withOpacity(0.55), blurRadius: 8, spreadRadius: 1)]
                : null,
          ),
        );
      }),
    );
  }
}

import 'package:flutter/material.dart';

/// 轮播页面指示器（圆点）
class PageIndicator extends StatelessWidget {
  final int count;
  final int current;
  final bool dark;

  const PageIndicator({
    super.key,
    required this.count,
    required this.current,
    this.dark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        final activeColor = dark ? Colors.white : Colors.white;
        final inactiveColor =
            dark ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

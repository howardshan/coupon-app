import 'package:flutter/material.dart';

/// Splash 右上角倒计时 + Skip 按钮
class CountdownSkipButton extends StatelessWidget {
  final AnimationController controller;
  final int durationSeconds;
  final VoidCallback onSkip;

  const CountdownSkipButton({
    super.key,
    required this.controller,
    required this.durationSeconds,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSkip,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          // 剩余秒数
          final remaining =
              (durationSeconds * (1 - controller.value)).ceil();
          return Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 圆形进度
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: controller.value,
                    strokeWidth: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                // 剩余秒数 + Skip 文字
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$remaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                    const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

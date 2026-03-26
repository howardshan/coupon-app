// 底部输入栏组件
// 包含文本输入框、图片按钮、发送按钮
// 发送按钮只在有文字输入时显示（AnimatedSwitcher 动画切换）

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 聊天底部输入栏
class ChatInputBar extends StatefulWidget {
  /// 发送文字消息回调
  final void Function(String text) onSendText;

  /// 选择图片回调（占位，暂不实现）
  final VoidCallback? onPickImage;

  /// 分享 Coupon 回调（占位，暂不实现）
  final VoidCallback? onPickCoupon;

  const ChatInputBar({
    super.key,
    required this.onSendText,
    this.onPickImage,
    this.onPickCoupon,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// 是否有输入内容（控制发送按钮显隐）
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 发送消息
  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFEEEEEE)),
        ),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        // 适配底部安全区域（刘海屏 / 全面屏）
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 8
            : MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 文本输入框
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 文本输入
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 4,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),

                  // 图片按钮（占位）
                  IconButton(
                    icon: const Icon(Icons.photo_camera_outlined,
                        color: AppColors.textSecondary),
                    onPressed: widget.onPickImage,
                    tooltip: 'Send image',
                    iconSize: 22,
                    padding: const EdgeInsets.only(right: 4, bottom: 6),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 发送按钮（有文字时显示，无文字时显示 Coupon 按钮）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: _hasText
                ? _SendButton(key: const ValueKey('send'), onTap: _send)
                : _CouponButton(
                    key: const ValueKey('coupon'),
                    onTap: widget.onPickCoupon,
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 发送按钮（橙色圆形）
// ============================================================

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SendButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_upward_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

// ============================================================
// Coupon 按钮（无文字时显示，占位）
// ============================================================

class _CouponButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _CouponButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.confirmation_number_outlined,
          color: AppColors.textSecondary,
          size: 22,
        ),
      ),
    );
  }
}

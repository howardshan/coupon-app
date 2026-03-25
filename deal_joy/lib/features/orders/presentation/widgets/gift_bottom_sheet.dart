// Gift Bottom Sheet — 发送礼品券给好友
// 支持 email 或 phone 输入，自动识别类型

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/coupons_provider.dart';

/// 礼品发送 Bottom Sheet
class GiftBottomSheet extends ConsumerStatefulWidget {
  const GiftBottomSheet({
    super.key,
    required this.dealTitle,
    required this.orderItemId,
    this.merchantName,
    this.expiresAt,
    this.onGiftSent,
    this.prefillEmail,
    this.prefillPhone,
  });

  final String dealTitle;
  final String orderItemId;
  final String? merchantName;
  final DateTime? expiresAt;
  final VoidCallback? onGiftSent;
  final String? prefillEmail;
  final String? prefillPhone;

  /// 静态方法：弹出 bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String dealTitle,
    required String orderItemId,
    String? merchantName,
    DateTime? expiresAt,
    VoidCallback? onGiftSent,
    String? prefillEmail,
    String? prefillPhone,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GiftBottomSheet(
        dealTitle: dealTitle,
        orderItemId: orderItemId,
        merchantName: merchantName,
        expiresAt: expiresAt,
        onGiftSent: onGiftSent,
        prefillEmail: prefillEmail,
        prefillPhone: prefillPhone,
      ),
    );
  }

  @override
  ConsumerState<GiftBottomSheet> createState() => _GiftBottomSheetState();
}

class _GiftBottomSheetState extends ConsumerState<GiftBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _recipientController;
  final TextEditingController _messageController = TextEditingController();

  /// 内联错误信息（非 SnackBar）
  String? _inlineError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 预填 email 优先，其次 phone
    final prefill = widget.prefillEmail ?? widget.prefillPhone ?? '';
    _recipientController = TextEditingController(text: prefill);
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // 输入类型识别
  // ----------------------------------------------------------------

  /// 判断输入是否为 email（包含 @）
  bool _isEmail(String value) => value.contains('@');

  /// 判断输入是否为 phone（去掉格式符号后全为数字，且不含 @）
  bool _isPhone(String value) {
    if (value.contains('@')) return false;
    final digits = value.replaceAll(RegExp(r'[\s\-().+]'), '');
    return RegExp(r'^\d+$').hasMatch(digits);
  }

  /// 提取纯数字（用于 phone 验证位数）
  String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[\s\-().+]'), '');

  // ----------------------------------------------------------------
  // 验证
  // ----------------------------------------------------------------

  String? _validateRecipient(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter an email or phone number';
    }
    final v = value.trim();
    if (_isEmail(v)) {
      // email 格式校验
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(v)) {
        return 'Please enter a valid email address';
      }
    } else if (_isPhone(v)) {
      // phone 至少 10 位数字
      if (_digitsOnly(v).length < 10) {
        return 'Phone number must have at least 10 digits';
      }
    } else {
      return 'Please enter a valid email or phone number';
    }
    return null;
  }

  // ----------------------------------------------------------------
  // 发送逻辑
  // ----------------------------------------------------------------

  Future<void> _handleSend() async {
    // 清空旧错误
    setState(() => _inlineError = null);

    if (!_formKey.currentState!.validate()) return;

    final recipient = _recipientController.text.trim();
    final message = _messageController.text.trim();

    setState(() => _isLoading = true);

    final success = await ref.read(giftNotifierProvider.notifier).sendGift(
          orderItemId: widget.orderItemId,
          recipientEmail: _isEmail(recipient) ? recipient : null,
          recipientPhone: _isPhone(recipient) ? _digitsOnly(recipient) : null,
          giftMessage: message.isNotEmpty ? message : null,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // 关闭 sheet
      Navigator.of(context).pop();
      // 回调通知上层刷新
      widget.onGiftSent?.call();
      // 成功 SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gift sent successfully!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // 读取 provider 中的错误信息，展示内联错误
      final giftState = ref.read(giftNotifierProvider);
      final errMsg = giftState.error?.toString() ?? 'Failed to send gift. Please try again.';
      setState(() => _inlineError = errMsg);
    }
  }

  // ----------------------------------------------------------------
  // UI 构建
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 键盘弹起时 bottom sheet 跟随上移
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽指示条
            _DragHandle(),
            const SizedBox(height: 20),

            // 标题
            const Text(
              'Send as a Gift',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Deal 信息行
            _DealInfoRow(
              dealTitle: widget.dealTitle,
              merchantName: widget.merchantName,
              expiresAt: widget.expiresAt,
            ),
            const SizedBox(height: 24),

            // "Send to" 标签
            const Text(
              'Send to',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // 收件人输入框（email 或 phone）
            TextFormField(
              controller: _recipientController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              validator: _validateRecipient,
              decoration: _inputDecoration(
                hint: 'Email or Phone Number',
                prefixIcon: Icons.person_outline,
              ),
            ),
            const SizedBox(height: 20),

            // "Add a message" 标签
            const Text(
              'Add a message (optional)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // 留言多行输入框
            TextFormField(
              controller: _messageController,
              maxLines: 3,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              decoration: _inputDecoration(
                hint: 'Write something nice...',
                prefixIcon: null,
                alignLabelWithHint: true,
              ),
            ),

            // 内联错误提示（仅在出错时显示）
            if (_inlineError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _inlineError!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Send Gift 按钮（渐变色圆角）
            _SendButton(
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _handleSend,
            ),
          ],
        ),
      ),
    );
  }

  /// 统一的 InputDecoration 样式
  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 15),
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
          : null,
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }
}

// ----------------------------------------------------------------
// 子组件
// ----------------------------------------------------------------

/// 顶部拖拽指示条
class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textHint,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Deal 信息行：标题 + 商家 + 过期日期
class _DealInfoRow extends StatelessWidget {
  const _DealInfoRow({
    required this.dealTitle,
    this.merchantName,
    this.expiresAt,
  });

  final String dealTitle;
  final String? merchantName;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    // 格式化过期日期：Apr 20, 2026
    final expiresLabel = expiresAt != null
        ? 'Expires: ${DateFormat('MMM d, yyyy').format(expiresAt!.toLocal())}'
        : null;

    // 组合副标题（商家 · 过期时间）
    final subtitle = [
      if (merchantName != null && merchantName!.isNotEmpty) merchantName!,
      ?expiresLabel,
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.card_giftcard_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dealTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Send Gift 渐变按钮
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed != null
              ? const LinearGradient(
                  colors: AppColors.primaryGradient,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: onPressed == null ? AppColors.textHint : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Send Gift',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// Gift Bottom Sheet — 发送礼品券给好友
// 支持 email / phone 输入 或 直接选择好友

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/coupons_provider.dart';
import '../../../chat/data/models/friend_model.dart';
import '../../../chat/domain/providers/friend_provider.dart';

/// 赠送模式
enum _GiftSendMode { emailPhone, friend }

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
    this.existingGiftId,
    this.dealImageUrl,
  });

  final String dealTitle;
  final String orderItemId;
  final String? merchantName;
  final DateTime? expiresAt;
  final VoidCallback? onGiftSent;
  final String? prefillEmail;
  final String? prefillPhone;
  /// 更换受赠方时，传入当前 gift 的 id，发送前先撤回旧 gift
  final String? existingGiftId;
  /// deal 图片 URL（好友模式发送 chat 消息时使用）
  final String? dealImageUrl;

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
    String? existingGiftId,
    String? dealImageUrl,
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
        existingGiftId: existingGiftId,
        dealImageUrl: dealImageUrl,
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

  /// 当前发送模式
  _GiftSendMode _sendMode = _GiftSendMode.emailPhone;

  /// 已选中的好友
  FriendModel? _selectedFriend;

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
    setState(() => _inlineError = null);

    // 好友模式：验证选择 + 调用 sendGiftToFriend
    if (_sendMode == _GiftSendMode.friend) {
      if (_selectedFriend == null) {
        setState(() => _inlineError = 'Please select a friend');
        return;
      }

      final message = _messageController.text.trim();
      setState(() => _isLoading = true);

      // 好友赠送模式：先撤回旧 gift（如果有）
      if (widget.existingGiftId != null) {
        final recalled = await ref
            .read(giftNotifierProvider.notifier)
            .recallGift(widget.existingGiftId!);
        if (!recalled) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _inlineError = 'Failed to recall existing gift. Please try again.';
          });
          return;
        }
      }

      final success =
          await ref.read(giftNotifierProvider.notifier).sendGiftToFriend(
                orderItemId: widget.orderItemId,
                recipientUserId: _selectedFriend!.friendId,
                giftMessage: message.isNotEmpty ? message : null,
                dealTitle: widget.dealTitle,
                dealImageUrl: widget.dealImageUrl,
                merchantName: widget.merchantName,
              );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.of(context).pop();
        widget.onGiftSent?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gift sent successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final giftState = ref.read(giftNotifierProvider);
        final errMsg = giftState.error?.toString() ??
            'Failed to send gift. Please try again.';
        setState(() => _inlineError = errMsg);
      }
      return;
    }

    // Email/Phone 模式：现有逻辑
    if (!_formKey.currentState!.validate()) return;

    final recipient = _recipientController.text.trim();
    final message = _messageController.text.trim();

    setState(() => _isLoading = true);

    // 更换受赠方模式：先撤回旧 gift，再发送新 gift
    if (widget.existingGiftId != null) {
      final recalled = await ref
          .read(giftNotifierProvider.notifier)
          .recallGift(widget.existingGiftId!);
      if (!recalled) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _inlineError = 'Failed to recall existing gift. Please try again.';
        });
        return;
      }
    }

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
      final errMsg =
          giftState.error?.toString() ?? 'Failed to send gift. Please try again.';
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

            // 发送模式切换
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<_GiftSendMode>(
                segments: const [
                  ButtonSegment(
                    value: _GiftSendMode.emailPhone,
                    label: Text('Email / Phone'),
                    icon: Icon(Icons.email_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _GiftSendMode.friend,
                    label: Text('Friends'),
                    icon: Icon(Icons.people_outline, size: 18),
                  ),
                ],
                selected: {_sendMode},
                onSelectionChanged: (v) => setState(() {
                  _sendMode = v.first;
                  _selectedFriend = null;
                  _inlineError = null;
                }),
                style: SegmentedButton.styleFrom(
                  selectedForegroundColor: AppColors.primary,
                  selectedBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Email/Phone 模式：显示 "Send to" 标签 + 收件人输入框
            if (_sendMode == _GiftSendMode.emailPhone) ...[
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
            ],

            // 好友模式：显示好友选择器
            if (_sendMode == _GiftSendMode.friend) ...[
              const Text(
                'Select a friend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // 已选好友展示
              if (_selectedFriend != null)
                _SelectedFriendChip(
                  friend: _selectedFriend!,
                  onRemove: () => setState(() => _selectedFriend = null),
                ),

              // 好友列表（未选时显示）
              if (_selectedFriend == null)
                _FriendPickerList(
                  onSelect: (friend) =>
                      setState(() => _selectedFriend = friend),
                ),
              const SizedBox(height: 20),
            ],

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

/// 已选好友展示 Chip
class _SelectedFriendChip extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onRemove;

  const _SelectedFriendChip({required this.friend, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.surfaceVariant,
            backgroundImage: friend.avatarUrl != null
                ? CachedNetworkImageProvider(friend.avatarUrl!)
                : null,
            child: friend.avatarUrl == null
                ? Text(
                    friend.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            friend.displayName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (friend.username != null) ...[
            const SizedBox(width: 4),
            Text(
              '@${friend.username}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 好友选择列表（单选）
class _FriendPickerList extends ConsumerWidget {
  final void Function(FriendModel friend) onSelect;

  const _FriendPickerList({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);

    return friendsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Failed to load friends',
          style: TextStyle(color: AppColors.textHint),
        ),
      ),
      data: (friends) {
        if (friends.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No friends yet. Add friends in Chat to gift them coupons.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: friends.length,
            itemBuilder: (_, i) {
              final friend = friends[i];
              return ListTile(
                dense: true,
                onTap: () => onSelect(friend),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surfaceVariant,
                  backgroundImage: friend.avatarUrl != null
                      ? CachedNetworkImageProvider(friend.avatarUrl!)
                      : null,
                  child: friend.avatarUrl == null
                      ? Text(
                          friend.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  friend.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                subtitle: friend.username != null
                    ? Text(
                        '@${friend.username}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      )
                    : null,
                trailing: const Icon(
                  Icons.card_giftcard,
                  size: 18,
                  color: AppColors.primary,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../chat/data/repositories/chat_repository.dart';
import '../../../chat/domain/providers/chat_provider.dart';
import '../../../orders/data/models/order_item_model.dart';
import '../../../orders/data/models/order_model.dart';
import '../../../orders/domain/providers/orders_provider.dart';
import '../widgets/faq_data.dart';

/// 消息类型
enum _MsgType { system, user }

/// 聊天消息数据
class _ChatMessage {
  final String text;
  final _MsgType type;
  final List<FaqItem>? buttons;
  final List<OrderModel>? orders;

  /// 可退款的 order items（orderId + item 信息）
  final List<_RefundableItem>? refundableItems;

  const _ChatMessage({
    required this.text,
    required this.type,
    this.buttons,
    this.orders,
    this.refundableItems,
  });
}

/// 可退款 item 信息
class _RefundableItem {
  final String orderId;
  final String itemId;
  final String? couponId;
  final String dealTitle;
  final String? imageUrl;
  final double unitPrice;
  final bool isUsed;

  const _RefundableItem({
    required this.orderId,
    required this.itemId,
    this.couponId,
    required this.dealTitle,
    this.imageUrl,
    required this.unitPrice,
    required this.isUsed,
  });
}

/// 预设问答树聊天界面
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _messages = <_ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loadingOrders = false;

  @override
  void initState() {
    super.initState();
    // 欢迎消息 + 快捷按钮
    _messages.add(_ChatMessage(
      text: 'Hi! 👋 Welcome to Crunchy Plum Support.\nHow can I help you today?',
      type: _MsgType.system,
      buttons: kFaqItems,
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 处理用户选择/输入
  Future<void> _handleInput(String input, {FaqItem? faqItem}) async {
    // 添加用户消息
    setState(() {
      _messages.add(_ChatMessage(text: input, type: _MsgType.user));
    });
    _scrollToBottom();

    // 匹配 FAQ
    final matched = faqItem ?? matchFaq(input);

    if (matched == null) {
      // 无匹配 → 兜底
      final fallback = kFaqItems.firstWhere((f) => f.id == 'other');
      _addSystemMessage(fallback.response, showMainMenu: true);
      return;
    }

    switch (matched.action) {
      case FaqAction.showOrders:
        await _handleShowOrders();
      case FaqAction.showRefundableOrders:
        await _handleShowRefundable();
      case FaqAction.goBack:
        _addSystemMessage(matched.response, showMainMenu: true);
      case FaqAction.none:
        _addSystemMessage(
          matched.response,
          showMainMenu: true,
        );
    }
  }

  /// 展示用户最近订单
  Future<void> _handleShowOrders() async {
    setState(() => _loadingOrders = true);
    _scrollToBottom();

    try {
      final orders = await ref.read(userOrdersProvider.future);
      final recent = orders.take(5).toList();

      setState(() {
        _loadingOrders = false;
        if (recent.isEmpty) {
          _messages.add(_ChatMessage(
            text: 'You don\'t have any orders yet. Start exploring deals on the home page!',
            type: _MsgType.system,
            buttons: kFaqItems,
          ));
        } else {
          _messages.add(_ChatMessage(
            text: 'Here are your recent orders:',
            type: _MsgType.system,
            orders: recent,
            buttons: kFaqItems,
          ));
        }
      });
    } catch (e) {
      setState(() {
        _loadingOrders = false;
        _messages.add(_ChatMessage(
          text: 'Sorry, I couldn\'t load your orders. Please try again later.',
          type: _MsgType.system,
          buttons: kFaqItems,
        ));
      });
    }
    _scrollToBottom();
  }

  /// 展示可退款订单
  Future<void> _handleShowRefundable() async {
    setState(() => _loadingOrders = true);
    _scrollToBottom();

    try {
      final orders = await ref.read(userOrdersProvider.future);
      // 找出所有 unused 的 item（可退款）
      final refundable = <_RefundableItem>[];
      for (final order in orders) {
        for (final item in order.items) {
          final isUnused = item.customerStatus == CustomerItemStatus.unused;
          final isUsed = item.customerStatus == CustomerItemStatus.used;
          if (isUnused || isUsed) {
            refundable.add(_RefundableItem(
              orderId: order.id,
              itemId: item.id,
              couponId: item.couponId,
              dealTitle: item.dealTitle,
              imageUrl: item.dealImageUrl,
              unitPrice: item.unitPrice,
              isUsed: isUsed,
            ));
          }
        }
      }

      setState(() {
        _loadingOrders = false;
        if (refundable.isEmpty) {
          _messages.add(_ChatMessage(
            text: 'You don\'t have any orders eligible for refund right now.\n\n'
                'Only unused coupons can be refunded.',
            type: _MsgType.system,
            buttons: kFaqItems,
          ));
        } else {
          _messages.add(_ChatMessage(
            text: 'Here are your orders eligible for refund. Tap one to start:',
            type: _MsgType.system,
            refundableItems: refundable,
            buttons: kFaqItems,
          ));
        }
      });
    } catch (e) {
      setState(() {
        _loadingOrders = false;
        _messages.add(_ChatMessage(
          text: 'Sorry, I couldn\'t load your orders. Please try again later.',
          type: _MsgType.system,
          buttons: kFaqItems,
        ));
      });
    }
    _scrollToBottom();
  }

  void _addSystemMessage(String text, {bool showMainMenu = false}) {
    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        type: _MsgType.system,
        buttons: showMainMenu ? kFaqItems : null,
      ));
    });
    _scrollToBottom();
  }

  void _onSend() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _handleInput(text);
  }

  bool _connectingToAgent = false;

  Future<void> _handleLiveAgent() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _connectingToAgent = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final conv = await chatRepo.getOrCreateSupportChat(user.id);
      if (!mounted) return;
      context.push('/chat/${conv.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _connectingToAgent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Crunchy Plum Support'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_loadingOrders ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _loadingOrders) {
                  return const _TypingIndicator();
                }
                return _MessageBubble(
                  message: _messages[index],
                  onFaqTap: (faq) => _handleInput(faq.label, faqItem: faq),
                  onOrderTap: (orderId) => context.push('/order/$orderId'),
                  onRefundTap: (item) {
                    if (item.isUsed) {
                      context.push('/after-sales/${item.orderId}');
                    } else if (item.couponId != null) {
                      context.push('/coupon/${item.couponId}');
                    } else {
                      context.push('/after-sales/${item.orderId}');
                    }
                  },
                );
              },
            ),
          ),

          // 输入栏
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _connectingToAgent ? null : _handleLiveAgent,
                    icon: _connectingToAgent
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('🎧', style: TextStyle(fontSize: 14)),
                    label: Text(
                      _connectingToAgent ? 'Connecting...' : 'Live Agent',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _onSend(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _onSend,
                  icon: const Icon(Icons.send_rounded),
                  color: AppColors.primary,
                ),
              ],
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 消息气泡 ──────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final void Function(FaqItem) onFaqTap;
  final void Function(String orderId) onOrderTap;
  final void Function(_RefundableItem) onRefundTap;

  const _MessageBubble({
    required this.message,
    required this.onFaqTap,
    required this.onOrderTap,
    required this.onRefundTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.type == _MsgType.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 气泡
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isUser ? Colors.white : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),

          // 订单列表
          if (message.orders != null) ...[
            const SizedBox(height: 8),
            ...message.orders!.map((order) => _OrderCard(
                  order: order,
                  onTap: () => onOrderTap(order.id),
                )),
          ],

          // 可退款列表
          if (message.refundableItems != null) ...[
            const SizedBox(height: 8),
            ...message.refundableItems!.map((item) => _RefundableCard(
                  item: item,
                  onTap: () => onRefundTap(item),
                )),
          ],

          // 快捷按钮
          if (message.buttons != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: message.buttons!.map((faq) {
                return ActionChip(
                  label: Text(
                    faq.label,
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () => onFaqTap(faq),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 订单卡片 ──────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 取第一个 item 的标题和图片作为缩略展示
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final title = firstItem?.dealTitle ?? 'Order';
    final status = firstItem?.customerStatus.displayLabel ?? '';
    final imageUrl = firstItem?.dealImageUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Row(
              children: [
                // 缩略图
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '\$${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (status.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              status,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.receipt_long, size: 20, color: AppColors.textHint),
    );
  }
}

// ─── 可退款 item 卡片 ────────────────────────────────────────────────

class _RefundableCard extends StatelessWidget {
  final _RefundableItem item;
  final VoidCallback onTap;

  const _RefundableCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.imageUrl != null
                      ? Image.network(
                          item.imageUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.dealTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${item.unitPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.isUsed
                        ? const Color(0xFFFF9800).withValues(alpha: 0.1)
                        : const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.isUsed ? 'Used' : 'To Use',
                    style: TextStyle(
                      fontSize: 11,
                      color: item.isUsed ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 44,
      height: 44,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.receipt_long, size: 20, color: AppColors.textHint),
    );
  }
}

// ─── 正在输入指示器 ──────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textHint,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Looking up your info...',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

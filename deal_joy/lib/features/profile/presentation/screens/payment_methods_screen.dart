import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/saved_card_model.dart';
import '../../domain/providers/payment_methods_provider.dart';

/// 已保存卡片管理页面
/// 支持：查看列表 / 设为默认 / 左滑删除 / 添加新卡
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(paymentMethodsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment Methods'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: cardsAsync.when(
        data: (cards) => _CardListBody(cards: cards),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text(
                  'Failed to load cards',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => ref.invalidate(paymentMethodsProvider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      // 底部"添加新卡"按钮
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _AddCardButton(),
        ),
      ),
    );
  }
}

// ── 卡片列表主体 ──────────────────────────────────────────────────────────────
class _CardListBody extends ConsumerWidget {
  final List<SavedCard> cards;
  const _CardListBody({required this.cards});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off_outlined, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text(
              'No saved cards',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add a card below to save it for faster checkout',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final card = cards[index];
        return _CardTile(card: card);
      },
    );
  }
}

// ── 单张卡片 Tile（点击打开操作底部弹层）─────────────────────────────────────
class _CardTile extends ConsumerWidget {
  final SavedCard card;
  const _CardTile({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showCardOptions(context, ref),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: card.isDefault ? AppColors.primary : AppColors.surfaceVariant,
            width: card.isDefault ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 卡片品牌图标
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(card.brandIcon, size: 22, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            // 卡号 + 过期日期
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${card.brandDisplayName} ${card.displayText}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (card.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expires ${card.expiryText}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (card.billingAddress != null && card.billingAddress!.summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      card.billingAddress!.summary,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // 右箭头提示可点击
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  /// 点击卡片后弹出操作底部弹层：详情 / 设为默认 / 删除
  void _showCardOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CardOptionsSheet(card: card, ref: ref),
    );
  }
}

// ── 添加新卡按钮 ──────────────────────────────────────────────────────────────
class _AddCardButton extends ConsumerStatefulWidget {
  const _AddCardButton();

  @override
  ConsumerState<_AddCardButton> createState() => _AddCardButtonState();
}

class _AddCardButtonState extends ConsumerState<_AddCardButton> {
  // 正在调用 Stripe 时为 true，防止重复点击
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      // 加载中时传 null 禁用按钮，避免重复触发 Stripe 弹窗
      onPressed: _isLoading ? null : _addNewCard,
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.add, size: 18),
      label: Text(_isLoading ? 'Connecting...' : 'Add New Card'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isLoading ? AppColors.primary.withValues(alpha: 0.6) : AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 通过 Stripe SetupSheet 添加新卡
  Future<void> _addNewCard() async {
    if (_isLoading) return; // 双重保险，防止并发
    setState(() => _isLoading = true);
    try {
      // 调用后端创建 SetupIntent，获取 clientSecret / customerId / ephemeralKey
      final setupData = await ref
          .read(paymentMethodsRepositoryProvider)
          .createSetupIntent();

      final clientSecret = setupData['clientSecret'] ?? '';
      final customerId = setupData['customerId'];
      final ephemeralKey = setupData['ephemeralKey'];

      if (clientSecret.isEmpty) {
        throw Exception('Invalid setup intent');
      }

      // 初始化 Stripe SetupPaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: clientSecret,
          merchantDisplayName: 'DealJoy',
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKey,
          style: ThemeMode.light,
          // 强制收集 billing address，确保卡片和地址绑定
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
            address: AddressCollectionMode.full,
          ),
        ),
      );

      // Stripe 弹窗出现前恢复按钮，避免弹窗期间按钮一直灰显
      if (mounted) setState(() => _isLoading = false);

      // 弹出卡片录入表单
      await Stripe.instance.presentPaymentSheet();

      // 成功后刷新卡片列表
      await ref.read(paymentMethodsProvider.notifier).refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card added successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on StripeException catch (e) {
      // 用户主动取消，不提示错误
      if (e.error.code == FailureCode.Canceled) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add card: ${e.error.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add card: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ── 卡片操作底部弹层：详情 / 设为默认 / 删除 ────────────────────────────────
class _CardOptionsSheet extends ConsumerStatefulWidget {
  final SavedCard card;
  final WidgetRef ref;

  const _CardOptionsSheet({required this.card, required this.ref});

  @override
  ConsumerState<_CardOptionsSheet> createState() => _CardOptionsSheetState();
}

class _CardOptionsSheetState extends ConsumerState<_CardOptionsSheet> {
  bool _isSettingDefault = false;
  bool _isDeleting = false;

  SavedCard get card => widget.card;

  /// 设为默认卡
  Future<void> _setDefault() async {
    setState(() => _isSettingDefault = true);
    try {
      await ref.read(paymentMethodsProvider.notifier).setDefault(card.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${card.brandDisplayName} ${card.displayText} set as default'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set default: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettingDefault = false);
    }
  }

  /// 删除卡片（含二次确认）
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Card'),
        content: Text(
          'Remove ${card.brandDisplayName} ${card.displayText}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(paymentMethodsProvider.notifier).deleteCard(card.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${card.brandDisplayName} ${card.displayText} removed'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove card: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addr = card.billingAddress;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(card.brandIcon, size: 22, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${card.brandDisplayName} ${card.displayText}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Expires ${card.expiryText}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (card.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),

          // 账单地址详情（若有）
          if (addr != null && addr.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text(
              'Billing Address',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            if (addr.line1.isNotEmpty)
              Text(addr.line1,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            if (addr.line2.isNotEmpty)
              Text(addr.line2,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            if (addr.city.isNotEmpty || addr.state.isNotEmpty || addr.postalCode.isNotEmpty)
              Text(
                [addr.city, addr.state, addr.postalCode]
                    .where((s) => s.isNotEmpty)
                    .join(', '),
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            if (addr.country.isNotEmpty)
              Text(addr.country,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ],

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // 设为默认（仅非默认卡显示）
          if (!card.isDefault)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.star_outline, color: AppColors.primary),
              title: const Text('Set as Default',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              trailing: _isSettingDefault
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right, color: AppColors.textHint),
              onTap: _isSettingDefault ? null : _setDefault,
            ),

          // 删除卡片
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _isDeleting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                  )
                : const Icon(Icons.delete_outline, color: AppColors.error),
            title: Text(
              'Remove Card',
              style: TextStyle(
                color: _isDeleting ? AppColors.textHint : AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: _isDeleting ? null : _delete,
          ),
        ],
      ),
    );
  }
}

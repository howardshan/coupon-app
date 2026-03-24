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

// ── 单张卡片 Tile（支持左滑删除 + 点击设默认）────────────────────────────────
class _CardTile extends ConsumerWidget {
  final SavedCard card;
  const _CardTile({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(paymentMethodsProvider.notifier);

    return Dismissible(
      key: ValueKey(card.id),
      direction: DismissDirection.endToStart,
      // 左滑显示红色删除背景
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        try {
          await notifier.deleteCard(card.id);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete card: $e')),
            );
          }
        }
      },
      child: GestureDetector(
        onTap: card.isDefault
            ? null
            : () async {
                try {
                  await notifier.setDefault(card.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${card.brandDisplayName} ••••${card.last4} set as default'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update default card: $e')),
                    );
                  }
                }
              },
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
                          // 默认标签
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // 如果有 billing address，显示摘要（单行截断）
                    if (card.billingAddress != null && card.billingAddress!.summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        card.billingAddress!.summary,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // 非默认卡显示"点击设为默认"提示箭头
              if (!card.isDefault)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除前确认弹窗
  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
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
  }
}

// ── 添加新卡按钮 ──────────────────────────────────────────────────────────────
class _AddCardButton extends ConsumerWidget {
  const _AddCardButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _addNewCard(context, ref),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add New Card'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 通过 Stripe SetupSheet 添加新卡
  Future<void> _addNewCard(BuildContext context, WidgetRef ref) async {
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
    }
  }
}

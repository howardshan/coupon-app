// 广告账户余额展示卡片
// 显示当前余额、Recharge 按钮、低余额警告

import 'package:flutter/material.dart';
import '../models/promotions_models.dart';

// =============================================================
// BalanceCard — 余额展示卡片（纯展示 StatelessWidget）
// =============================================================
class BalanceCard extends StatelessWidget {
  /// 广告账户数据
  final AdAccount account;

  /// 点击充值按钮回调
  final VoidCallback onRecharge;

  /// 低余额阈值（低于此值显示警告，默认 $20）
  final double lowBalanceThreshold;

  const BalanceCard({
    super.key,
    required this.account,
    required this.onRecharge,
    this.lowBalanceThreshold = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final isLowBalance = account.balance < lowBalanceThreshold;

    return Column(
      children: [
        // --------------------------------------------------------
        // 主余额卡片
        // --------------------------------------------------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A1A2E).withAlpha(51),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Ad Balance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 余额金额
              Text(
                '\$${account.balance.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),

              // 活跃计划数（AdAccount 无独立 status 字段）
              Text(
                account.activeCampaignCount == 1
                    ? '1 active campaign'
                    : '${account.activeCampaignCount} active campaigns',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),

              // Recharge 按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRecharge,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Recharge',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),

        // --------------------------------------------------------
        // 低余额警告横幅（仅在余额不足时显示）
        // --------------------------------------------------------
        if (isLowBalance) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD700), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB8860B),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Low balance! Your campaigns may pause soon. '
                    'Recharge to keep them running.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A5C00),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

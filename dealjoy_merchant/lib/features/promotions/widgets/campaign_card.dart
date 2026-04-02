// Campaign 列表卡片组件
// 显示广告位、Target、出价、今日消费进度条、状态徽章
// 支持右滑操作：Pause / Resume / Delete

import 'package:flutter/material.dart';
import '../models/promotions_models.dart';

// =============================================================
// CampaignCard — Campaign 列表卡片（StatelessWidget）
// =============================================================
class CampaignCard extends StatelessWidget {
  final AdCampaign campaign;
  final VoidCallback onTap;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onDelete;

  const CampaignCard({
    super.key,
    required this.campaign,
    required this.onTap,
    this.onPause,
    this.onResume,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('campaign_${campaign.id}'),
      // 右滑显示操作按钮
      background: _buildSwipeBackground(),
      secondaryBackground: _buildDeleteBackground(),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // 右滑：Pause / Resume（与 Edge pause/resume 规则对齐）
          final s = campaign.status;
          if ((s == CampaignStatus.active || s == CampaignStatus.exhausted) &&
              onPause != null) {
            onPause!();
          } else if (s == CampaignStatus.paused && onResume != null) {
            onResume!();
          }
          return false; // 不真正移除
        } else {
          // 左滑：删除确认
          return await _confirmDelete(context);
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart && onDelete != null) {
          onDelete!();
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -----------------------------------------------
              // 顶部行：广告位图标 + 名称 + 状态徽章
              // -----------------------------------------------
              Row(
                children: [
                  _PlacementIcon(placement: campaign.placement),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      campaign.placementDisplayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  _StatusBadge(status: campaign.status),
                ],
              ),
              const SizedBox(height: 10),

              // -----------------------------------------------
              // Target 信息
              // -----------------------------------------------
              Row(
                children: [
                  Icon(
                    campaign.targetType == TargetType.deal
                        ? Icons.local_offer_outlined
                        : Icons.store_outlined,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Target: ${campaign.targetId}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // -----------------------------------------------
              // 出价 + 日预算
              // -----------------------------------------------
              Row(
                children: [
                  Text(
                    '\$${campaign.bidPrice.toStringAsFixed(2)}/click',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                  const Text(
                    '  ·  ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  Text(
                    'Budget: \$${campaign.dailyBudget.toStringAsFixed(0)}/day',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // -----------------------------------------------
              // 今日消费进度条
              // -----------------------------------------------
              _SpendProgressBar(
                todaySpend: campaign.todaySpend,
                dailyBudget: campaign.dailyBudget,
              ),

              // admin 暂停提示
              if (campaign.status == CampaignStatus.adminPaused) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline,
                          size: 13, color: Color(0xFFE53935)),
                      SizedBox(width: 4),
                      Text(
                        'Paused by admin — contact support',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 右滑背景（Pause / Resume）
  // ----------------------------------------------------------
  Widget _buildSwipeBackground() {
    final isPaused = campaign.status == CampaignStatus.paused;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isPaused ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            isPaused ? 'Resume' : 'Pause',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 左滑背景（Delete）
  // ----------------------------------------------------------
  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 28),
          SizedBox(height: 4),
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 删除确认对话框
  // ----------------------------------------------------------
  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Campaign'),
        content: const Text(
            'This campaign and all its data will be permanently deleted. '
            'Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

}

// =============================================================
// _PlacementIcon — 广告位图标（私有组件）
// =============================================================
class _PlacementIcon extends StatelessWidget {
  final String placement;

  const _PlacementIcon({required this.placement});

  @override
  Widget build(BuildContext context) {
    final data = _iconData(placement);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: data.color.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(data.icon, size: 18, color: data.color),
    );
  }

  _IconData _iconData(String placement) {
    switch (placement) {
      case 'home_featured':
        return _IconData(Icons.home_outlined, const Color(0xFFFF6B35));
      case 'search_top':
        return _IconData(Icons.search, const Color(0xFF2196F3));
      case 'category_banner':
        return _IconData(Icons.category_outlined, const Color(0xFF9C27B0));
      case 'deal_related':
        return _IconData(Icons.local_offer_outlined, const Color(0xFF4CAF50));
      default:
        return _IconData(Icons.campaign_outlined, const Color(0xFF607D8B));
    }
  }
}

class _IconData {
  final IconData icon;
  final Color color;
  const _IconData(this.icon, this.color);
}

// =============================================================
// _StatusBadge — 状态徽章（私有组件）
// =============================================================
class _StatusBadge extends StatelessWidget {
  final CampaignStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final label = _label(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _color(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.active:
        return const Color(0xFF4CAF50);
      case CampaignStatus.paused:
        return const Color(0xFFFF9800);
      case CampaignStatus.exhausted:
        return const Color(0xFFFF7043);
      case CampaignStatus.ended:
        return const Color(0xFF2196F3);
      case CampaignStatus.adminPaused:
        return const Color(0xFFE53935);
    }
  }

  String _label(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.active:
        return 'Active';
      case CampaignStatus.paused:
        return 'Paused';
      case CampaignStatus.exhausted:
        return 'Exhausted';
      case CampaignStatus.ended:
        return 'Ended';
      case CampaignStatus.adminPaused:
        return 'Admin';
    }
  }
}

// =============================================================
// _SpendProgressBar — 今日消费进度条（私有组件）
// =============================================================
class _SpendProgressBar extends StatelessWidget {
  final double todaySpend;
  final double dailyBudget;

  const _SpendProgressBar({
    required this.todaySpend,
    required this.dailyBudget,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        dailyBudget > 0 ? (todaySpend / dailyBudget).clamp(0.0, 1.0) : 0.0;
    final isNearLimit = progress >= 0.8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Today: \$${todaySpend.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: isNearLimit
                    ? const Color(0xFFE53935)
                    : Colors.grey.shade600,
                fontWeight:
                    isNearLimit ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            Text(
              'Budget: \$${dailyBudget.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              isNearLimit
                  ? const Color(0xFFE53935)
                  : const Color(0xFFFF6B35),
            ),
          ),
        ),
      ],
    );
  }
}

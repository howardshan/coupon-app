// 单条核销记录组件
// 显示: Deal名/用户名/券码/核销时间/已撤销状态

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/coupon_info.dart';

class RedemptionRecordTile extends StatelessWidget {
  const RedemptionRecordTile({
    super.key,
    required this.record,
  });

  final RedemptionRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        DateFormat('MMM d, yyyy h:mm a').format(record.redeemedAt.toLocal());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: record.isReverted
                    ? Colors.grey.shade100
                    : const Color(0xFFFFF3EE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                record.isReverted
                    ? Icons.undo_rounded
                    : Icons.check_circle_outline_rounded,
                color: record.isReverted
                    ? Colors.grey.shade500
                    : const Color(0xFFFF6B35),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.dealTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (record.isReverted) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Reverted',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  Text(
                    record.userName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),

                  Text(
                    record.couponCode,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Text(
                    timeStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

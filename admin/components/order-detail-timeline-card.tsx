import AdminActivityTimelineCard from '@/components/admin-activity-timeline-card'
import type { OrderTimelineEntry } from '@/lib/order-admin-timeline'

/** 订单状态变更时间线（由数据库时间字段推导）；UI 复用通用 Activity 卡片 */
export default function OrderDetailTimelineCard({ events }: { events: OrderTimelineEntry[] }) {
  return (
    <AdminActivityTimelineCard
      title="Activity timeline"
      footnote="Derived from payment, refund, gift, and voucher timestamps. Intermediate approval steps may not appear if not stored separately."
      events={events}
    />
  )
}

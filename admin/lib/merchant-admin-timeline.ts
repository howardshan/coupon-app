/**
 * Merchant 详情页 — 活动时间线
 * 优先使用 merchant_activity_events 审计表；无历史行时回退到 merchants 行内字段推导。
 * 注释中文；展示文案英文。
 */

import {
  sortActivityTimelineAscending,
  type AdminActivityTimelineEntry,
} from '@/lib/admin-activity-timeline-types'
import type { MerchantActivityEventTypeDb } from '@/lib/merchant-activity-events'

export type MerchantTimelineMerchantLike = {
  created_at?: string | null
  updated_at?: string | null
  submitted_at?: string | null
  status?: string | null
  rejection_reason?: string | null
}

/** 详情页查询的活动事件行（含可选操作者邮箱） */
export type MerchantActivityEventRow = {
  created_at: string
  event_type: MerchantActivityEventTypeDb | string
  actor_type: string
  actor_user_id?: string | null
  detail?: string | null
  users?: { email?: string | null } | { email?: string | null }[] | null
}

function actorEmail(row: MerchantActivityEventRow): string | null {
  const u = row.users
  if (u == null) return null
  const one = Array.isArray(u) ? u[0] : u
  const e = one?.email?.trim()
  return e || null
}

function actorSubtitle(row: MerchantActivityEventRow): string | undefined {
  const email = actorEmail(row)
  if (row.actor_type === 'admin') {
    return email ? `Admin · ${email}` : 'Admin'
  }
  if (row.actor_type === 'merchant_owner') {
    return email ? `Merchant owner · ${email}` : 'Merchant owner'
  }
  if (row.actor_type === 'system') return 'System'
  return email ?? undefined
}

function truncate(s: string, max: number): string {
  const t = s.trim()
  if (t.length <= max) return t
  return `${t.slice(0, max - 1)}…`
}

function mapEventRowToEntry(row: MerchantActivityEventRow): AdminActivityTimelineEntry | null {
  const at = String(row.created_at ?? '').trim()
  if (!at) return null

  const sub = actorSubtitle(row)
  const kind = row.event_type as MerchantActivityEventTypeDb

  switch (kind) {
    case 'application_submitted':
      return {
        at,
        title: 'Application submitted for review',
        subtitle: sub,
      }
    case 'admin_approved':
      return {
        at,
        title: 'Application approved',
        subtitle: sub,
      }
    case 'admin_rejected': {
      const reason = row.detail?.trim()
      return {
        at,
        title: 'Application rejected',
        subtitle: [reason ? truncate(reason, 220) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'admin_revoked_to_pending':
      return {
        at,
        title: 'Approval revoked — back to pending review',
        subtitle: sub,
      }
    case 'store_online_merchant':
      return {
        at,
        title: 'Store set visible online',
        subtitle: sub ?? 'Merchant dashboard',
      }
    case 'store_offline_merchant':
      return {
        at,
        title: 'Store set offline',
        subtitle: sub ?? 'Merchant dashboard',
      }
    case 'store_online_admin':
      return {
        at,
        title: 'Store set visible online',
        subtitle: sub ?? 'Admin',
      }
    case 'store_offline_admin':
      return {
        at,
        title: 'Store set offline',
        subtitle: sub ?? 'Admin',
      }
    case 'store_closed_merchant':
      return {
        at,
        title: 'Store closed',
        subtitle: sub ?? 'Permanent close flow (deals deactivated, pending refunds)',
      }
    case 'stripe_unlink_approved': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Stripe disconnection request approved (platform unlinked)',
        subtitle: [d ? truncate(d, 200) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'stripe_unlink_rejected': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Stripe disconnection request not approved',
        subtitle: [d ? truncate(d, 200) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'admin_staff_invited': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Staff invitation or direct add (admin)',
        subtitle: [d ? truncate(d, 220) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'admin_staff_role_changed': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Staff role changed (admin)',
        subtitle: [d ? truncate(d, 220) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'admin_staff_removed': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Staff access removed (admin)',
        subtitle: [d ? truncate(d, 220) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    case 'admin_staff_status_changed': {
      const d = row.detail?.trim()
      return {
        at,
        title: 'Staff account enabled/disabled (admin)',
        subtitle: [d ? truncate(d, 220) : null, sub].filter(Boolean).join(' · ') || undefined,
      }
    }
    default:
      return {
        at,
        title: String(kind),
        subtitle: sub,
      }
  }
}

function push(
  out: AdminActivityTimelineEntry[],
  at: string | null | undefined,
  title: string,
  subtitle?: string
): void {
  if (at == null) return
  const t = String(at).trim()
  if (!t) return
  out.push({ at: t, title, subtitle: subtitle?.trim() || undefined })
}

function sameInstantWithinMs(
  a: string | null | undefined,
  b: string | null | undefined,
  ms: number
): boolean {
  if (a == null || b == null) return false
  return Math.abs(new Date(a).getTime() - new Date(b).getTime()) <= ms
}

/** 无审计表数据时的回退时间线（与 Phase 2 行为一致） */
function buildLegacyDerivedTimeline(merchant: MerchantTimelineMerchantLike): AdminActivityTimelineEntry[] {
  const out: AdminActivityTimelineEntry[] = []

  push(out, merchant.created_at, 'Merchant record created', 'Account / storefront row first created')

  const submitted = merchant.submitted_at
  const created = merchant.created_at
  if (submitted && !sameInstantWithinMs(submitted, created, 1000)) {
    push(out, submitted, 'Application submitted for review', 'Merchant completed onboarding submission')
  } else if (submitted && !created) {
    push(out, submitted, 'Application submitted for review')
  }

  const sorted = sortActivityTimelineAscending(out)
  const maxAt = sorted.reduce((acc, e) => Math.max(acc, new Date(e.at).getTime()), 0)
  const updatedRaw = merchant.updated_at
  const updatedMs = updatedRaw ? new Date(updatedRaw).getTime() : 0

  const status = merchant.status?.trim() || 'unknown'
  const reason = merchant.rejection_reason?.trim()
  const statusLine = `Current status: ${status}`
  const reasonLine =
    reason && status === 'rejected'
      ? ` · Rejection reason on file: ${reason.length > 160 ? `${reason.slice(0, 157)}…` : reason}`
      : ''

  if (updatedMs > maxAt + 1000) {
    sorted.push({
      at: String(updatedRaw).trim(),
      title: 'Record last updated',
      subtitle: `${statusLine}${reasonLine} — may reflect profile edits, commission changes, or review outcome without separate audit rows`,
    })
  }

  return sortActivityTimelineAscending(sorted)
}

/**
 * 组装 Merchant 时间线：审计事件 + 可选「建档」锚点 + 可选「其他更新」节点。
 */
export function buildMerchantTimeline(
  merchant: MerchantTimelineMerchantLike,
  activityEvents: MerchantActivityEventRow[] = []
): AdminActivityTimelineEntry[] {
  if (!activityEvents.length) {
    return buildLegacyDerivedTimeline(merchant)
  }

  const fromDb = activityEvents
    .map(mapEventRowToEntry)
    .filter((e): e is AdminActivityTimelineEntry => e != null)

  const sortedEvents = sortActivityTimelineAscending(fromDb)
  const firstAt = sortedEvents.length ? new Date(sortedEvents[0].at).getTime() : Infinity
  const createdMs = merchant.created_at ? new Date(merchant.created_at).getTime() : 0

  const out: AdminActivityTimelineEntry[] = []

  if (merchant.created_at && createdMs > 0 && createdMs < firstAt - 1000) {
    push(
      out,
      merchant.created_at,
      'Merchant record created',
      'Account / storefront row first created'
    )
  }

  out.push(...sortedEvents)

  let merged = sortActivityTimelineAscending(out)
  const maxAt = merged.reduce((acc, e) => Math.max(acc, new Date(e.at).getTime()), 0)
  const updatedRaw = merchant.updated_at
  const updatedMs = updatedRaw ? new Date(updatedRaw).getTime() : 0

  if (updatedMs > maxAt + 1000) {
    merged = [
      ...merged,
      {
        at: String(updatedRaw).trim(),
        title: 'Record last updated',
        subtitle:
          'Other database changes (e.g. profile, commission) not written as separate timeline events',
      },
    ]
    merged = sortActivityTimelineAscending(merged)
  }

  return merged
}

import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import {
  fetchPendingApprovalCounts,
  totalPendingApprovals,
} from '@/lib/admin-approval-counts'
import { fetchPlatformSnapshot } from '@/lib/admin-dashboard-stats'

async function getAdminDashboard() {
  const db = getServiceRoleClient()
  const [pending, snapshot] = await Promise.all([
    fetchPendingApprovalCounts(db),
    fetchPlatformSnapshot(db),
  ])
  return { pending, snapshot, totalPending: totalPendingApprovals(pending) }
}

async function getMerchantDashboard(userId: string) {
  const supabase = await createClient()
  const { data: merchant } = await supabase
    .from('merchants')
    .select('id, name')
    .eq('user_id', userId)
    .maybeSingle()

  if (!merchant) {
    return { merchantName: null as string | null, activeDealCount: 0, totalOrders: 0 }
  }

  const db = getServiceRoleClient()
  const [{ count: activeDealCount }, { count: totalOrders }] = await Promise.all([
    db
      .from('deals')
      .select('id', { count: 'exact', head: true })
      .eq('merchant_id', merchant.id)
      .eq('is_active', true),
    db.from('orders').select('id', { count: 'exact', head: true }).eq('merchant_id', merchant.id),
  ])

  return {
    merchantName: merchant.name,
    activeDealCount: activeDealCount ?? 0,
    totalOrders: totalOrders ?? 0,
  }
}

export default async function DashboardPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role === 'admin') {
    const { pending, snapshot, totalPending } = await getAdminDashboard()

    const pendingItems: {
      key: keyof typeof pending
      label: string
      description: string
      tab: string
      accent: string
      borderHover: string
    }[] = [
      {
        key: 'merchants',
        label: 'Merchant applications',
        description: 'New store onboarding',
        tab: 'merchants',
        accent: 'text-amber-700',
        borderHover: 'hover:border-amber-300 hover:bg-amber-50/50',
      },
      {
        key: 'deals',
        label: 'Deal reviews',
        description: 'Listings awaiting approval',
        tab: 'deals',
        accent: 'text-violet-700',
        borderHover: 'hover:border-violet-300 hover:bg-violet-50/50',
      },
      {
        key: 'refundDisputes',
        label: 'Refund arbitration',
        description: 'Platform decisions needed',
        tab: 'refund-disputes',
        accent: 'text-orange-700',
        borderHover: 'hover:border-orange-300 hover:bg-orange-50/50',
      },
      {
        key: 'afterSales',
        label: 'After-sales',
        description: 'Awaiting platform',
        tab: 'after-sales',
        accent: 'text-rose-700',
        borderHover: 'hover:border-rose-300 hover:bg-rose-50/50',
      },
      {
        key: 'stripeUnlink',
        label: 'Stripe unlink',
        description: 'Disconnect requests',
        tab: 'stripe-unlink',
        accent: 'text-sky-800',
        borderHover: 'hover:border-sky-300 hover:bg-sky-50/50',
      },
    ]

    return (
      <div className="space-y-8">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Overview</h1>
          <p className="mt-1 text-sm text-gray-500">
            Pending items match the Approvals center and sidebar badge.
          </p>
        </div>

        {/* 待办优先 */}
        <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm sm:p-6">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Needs attention</h2>
              <p className="mt-2 text-4xl font-bold tabular-nums text-gray-900">{totalPending}</p>
              <p className="mt-1 text-sm text-gray-600">Open tasks across all approval queues</p>
            </div>
            <Link
              href="/approvals"
              className="inline-flex min-h-[44px] shrink-0 items-center justify-center rounded-xl bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-blue-700"
            >
              Open Approvals
            </Link>
          </div>

          {totalPending === 0 ? (
            <p className="mt-6 rounded-xl border border-dashed border-gray-200 bg-gray-50 p-6 text-center text-sm text-gray-600">
              You&apos;re all caught up. No pending approvals.
            </p>
          ) : (
            <ul className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {pendingItems.map((item) => {
                const count = pending[item.key]
                const href = `/approvals?tab=${item.tab}&queue=pending`
                return (
                  <li key={item.key}>
                    <Link
                      href={href}
                      className={`block rounded-xl border border-gray-200 p-4 transition-colors ${item.borderHover}`}
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <p className="text-sm font-medium text-gray-900">{item.label}</p>
                          <p className="mt-0.5 text-xs text-gray-500">{item.description}</p>
                        </div>
                        <span className={`text-2xl font-bold tabular-nums ${item.accent}`}>{count}</span>
                      </div>
                    </Link>
                  </li>
                )
              })}
            </ul>
          )}
        </section>

        {/* 平台快照 */}
        <section>
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">Platform snapshot</h2>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
            <SnapshotCard label="Users (all)" value={snapshot.totalUsers} />
            <SnapshotCard label="Merchants" value={snapshot.totalMerchants} />
            <SnapshotCard label="Deals" value={snapshot.totalDeals} />
            <SnapshotCard label="Brands" value={snapshot.totalBrands} />
            <SnapshotCard label="Orders (7d)" value={snapshot.ordersLast7Days} highlight />
          </div>
          <p className="mt-2 text-xs text-gray-400">
            Totals are all-time; &quot;Orders (7d)&quot; counts orders created in the last 7 days (UTC).
          </p>
        </section>
      </div>
    )
  }

  const m = await getMerchantDashboard(user!.id)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        {m.merchantName && (
          <p className="mt-1 text-sm text-gray-600">
            Store: <span className="font-medium text-gray-900">{m.merchantName}</span>
          </p>
        )}
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <p className="text-sm text-gray-500">Active deals</p>
          <p className="mt-1 text-3xl font-bold text-blue-700 tabular-nums">{m.activeDealCount}</p>
          <Link href="/deals" className="mt-3 inline-block text-sm font-medium text-blue-600 hover:underline">
            Manage deals
          </Link>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <p className="text-sm text-gray-500">Total orders</p>
          <p className="mt-1 text-3xl font-bold text-emerald-700 tabular-nums">{m.totalOrders}</p>
          <p className="mt-2 text-xs text-gray-400">All-time orders for this store.</p>
        </div>
      </div>
    </div>
  )
}

function SnapshotCard({
  label,
  value,
  highlight,
}: {
  label: string
  value: number
  highlight?: boolean
}) {
  return (
    <div
      className={`rounded-xl border p-4 ${
        highlight ? 'border-blue-200 bg-blue-50/50' : 'border-gray-200 bg-white'
      }`}
    >
      <p className="text-xs font-medium text-gray-500">{label}</p>
      <p className={`mt-1 text-2xl font-bold tabular-nums ${highlight ? 'text-blue-800' : 'text-gray-900'}`}>
        {value}
      </p>
    </div>
  )
}

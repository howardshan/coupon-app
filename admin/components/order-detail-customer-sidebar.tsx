import Link from 'next/link'
import CopyTextButton from '@/components/copy-text-button'
import { UA_SECTION_TITLE, UA_SIDEBAR_CARD } from '@/lib/user-admin-ui'

export type OrderCustomerSummary = {
  id: string
  email: string | null
  full_name: string | null
  username: string | null
  role: string | null
  avatar_url: string | null
  phone: string | null
  created_at: string | null
}

function roleBadgeClass(role: string): string {
  switch (role) {
    case 'admin':
      return 'bg-rose-50 text-rose-800 ring-rose-600/15'
    case 'merchant':
      return 'bg-sky-50 text-sky-800 ring-sky-600/15'
    default:
      return 'bg-slate-100 text-slate-700 ring-slate-600/10'
  }
}

/** 订单详情页右侧：下单用户信息（与 /users/[id] 侧栏风格一致） */
export default function OrderDetailCustomerSidebar({
  customer,
  returnToPath,
}: {
  customer: OrderCustomerSummary | null
  returnToPath: string
}) {
  if (!customer?.id) {
    return (
      <div className={UA_SIDEBAR_CARD}>
        <h2 className="text-sm font-semibold tracking-tight text-slate-900">Customer</h2>
        <p className="mt-2 text-sm text-slate-500">No user linked to this order.</p>
      </div>
    )
  }

  const role = customer.role ?? 'user'
  const profileHref = `/users/${customer.id}?returnTo=${encodeURIComponent(returnToPath)}`
  const initial = (customer.full_name || customer.email || '?')[0]?.toUpperCase() ?? '?'

  return (
    <div className={UA_SIDEBAR_CARD}>
      <h2 className="text-sm font-semibold tracking-tight text-slate-900">Customer</h2>
      <p className="mt-1 text-xs text-slate-500">Account that placed this order.</p>

      <div className="mt-4 flex items-start gap-3">
        {customer.avatar_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- 外部头像 URL，与用户详情页一致
          <img
            src={customer.avatar_url}
            alt=""
            className="h-14 w-14 shrink-0 rounded-full border-2 border-slate-200 object-cover shadow-sm ring-2 ring-white"
          />
        ) : (
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border-2 border-slate-200 bg-gradient-to-br from-slate-100 to-slate-200 text-lg font-semibold text-slate-500 ring-2 ring-white">
            {initial}
          </div>
        )}
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-slate-900">{customer.full_name?.trim() || '—'}</p>
          <span
            className={`mt-1 inline-flex rounded-full px-2 py-0.5 text-xs font-semibold capitalize ring-1 ring-inset ${roleBadgeClass(role)}`}
          >
            {role}
          </span>
        </div>
      </div>

      <dl className="mt-4 space-y-3 text-sm">
        <div>
          <dt className={UA_SECTION_TITLE}>Email</dt>
          <dd className="mt-1 break-all text-slate-900">{customer.email ?? '—'}</dd>
        </div>
        <div>
          <dt className={UA_SECTION_TITLE}>Username</dt>
          <dd className="mt-1 font-mono text-slate-900">{customer.username?.trim() || '—'}</dd>
        </div>
        <div>
          <dt className={UA_SECTION_TITLE}>Phone</dt>
          <dd className="mt-1 text-slate-900">{customer.phone?.trim() || '—'}</dd>
        </div>
        <div>
          <dt className={UA_SECTION_TITLE}>User ID</dt>
          <dd className="mt-1 flex flex-wrap items-center gap-2">
            <span className="break-all font-mono text-xs text-slate-700">{customer.id}</span>
            <CopyTextButton text={customer.id} label="Copy" copiedLabel="Copied" />
          </dd>
        </div>
        {customer.created_at && (
          <div>
            <dt className={UA_SECTION_TITLE}>Joined</dt>
            <dd className="mt-1 text-slate-900">
              {new Date(customer.created_at).toLocaleDateString('en-US')}
            </dd>
          </div>
        )}
      </dl>

      <Link
        href={profileHref}
        className="mt-4 flex w-full items-center justify-center rounded-xl border border-slate-200/90 bg-white px-3 py-2 text-sm font-semibold text-blue-700 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:border-blue-200 hover:bg-blue-50/80"
      >
        View full profile
      </Link>
    </div>
  )
}

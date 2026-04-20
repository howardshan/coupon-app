import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import BanUserButton from '@/components/ban-user-button'
import UserDetailSpendingAndActivityModal from '@/components/user-detail-spending-and-activity-modal'
import RoleSelect from '@/components/role-select'
import UserDetailPasswordPanel from '@/components/user-detail-password-panel'
import UserBillingAddressesPanel, {
  type BillingAddressRow,
} from '@/components/user-billing-addresses-panel'
import UserStoreCreditPanel from '@/components/user-store-credit-panel'
import UserMerchantStaffSection from '@/components/user-merchant-staff-section'
import type { MerchantStaffAdminRowModel } from '@/components/merchant-staff-admin-row'
import { mapStoreCreditTransaction } from '@/lib/store-credit-map'
import ConsentStatusCard from '@/components/consent-status-card'
import LegalTimeline from '@/components/legal-timeline'
import { getUserConsentStatus, getUserLegalTimeline } from '@/app/actions/legal'

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user: currentUser } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', currentUser!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 用户基本信息
  const { data: userInfo } = await supabase
    .from('users')
    .select('id, email, full_name, role, avatar_url, bio, phone, username, date_of_birth, created_at, updated_at, last_login_at, registration_source')
    .eq('id', id)
    .single()

  if (!userInfo) {
    return (
      <div>
        <p className="text-gray-500">User not found.</p>
        <Link href="/users" className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50">
          ← Back to Users
        </Link>
      </div>
    )
  }

  // 检查是否被封禁（通过 auth.users 的 banned_until）
  const { data: authUser } = await serviceClient.auth.admin.getUserById(id)
  const bannedUntil = authUser?.user?.banned_until
  const isBanned = bannedUntil && new Date(bannedUntil) > new Date()
  const authEmail = authUser?.user?.email?.trim() ?? ''
  const hasEmail = authEmail.length > 0
  const identities = authUser?.user?.identities ?? []
  const emailIdentity = identities.some((i) => i.provider === 'email')
  const oauthOnly = identities.length > 0 && !emailIdentity

  // 购买记录（orders）— 用 service client 绕过 RLS
  const { data: orders } = await serviceClient
    .from('orders')
    .select('id, order_number, total_amount, status, created_at, deals(title, merchants(name)), order_items(id, deal_id, unit_price, customer_status, deals(title, merchants(name)))')
    .eq('user_id', id)
    .order('created_at', { ascending: false })
    .limit(50)

  // 券使用记录（coupons）— 用 service client 绕过 RLS
  const { data: coupons } = await serviceClient
    .from('coupons')
    .select('id, deal_id, status, qr_code, used_at, expires_at, created_at, void_reason, voided_at, deals(title, merchants(name))')
    .eq('user_id', id)
    .order('created_at', { ascending: false })
    .limit(50)

  // 统计（侧栏摘要 + 主列如需可复用）
  const totalSpent = orders?.reduce((sum, o) => sum + (Number(o.total_amount) || 0), 0) ?? 0
  const totalOrders = orders?.length ?? 0
  const usedCoupons = coupons?.filter(c => c.status === 'used').length ?? 0
  const activeCoupons = coupons?.filter(c => c.status === 'unused').length ?? 0
  const avgOrder = totalOrders > 0 ? totalSpent / totalOrders : 0

  // 用户账单地址（service role 绕过 RLS）
  const { data: billingAddressesRaw } = await serviceClient
    .from('billing_addresses')
    .select('*')
    .eq('user_id', id)
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: true })

  const billingAddresses: BillingAddressRow[] = (billingAddressesRaw ?? []).map((r) => ({
    id: String(r.id),
    user_id: String(r.user_id),
    label: String(r.label ?? ''),
    address_line1: String(r.address_line1 ?? ''),
    address_line2: String(r.address_line2 ?? ''),
    city: String(r.city ?? ''),
    state: String(r.state ?? ''),
    postal_code: String(r.postal_code ?? ''),
    country: String(r.country ?? 'US'),
    is_default: Boolean(r.is_default),
    created_at: String(r.created_at ?? ''),
    updated_at: String(r.updated_at ?? ''),
  }))

  const { data: storeCreditRow } = await serviceClient
    .from('store_credits')
    .select('amount')
    .eq('user_id', id)
    .maybeSingle()

  const storeCreditBalance = Math.round(Number(storeCreditRow?.amount ?? 0) * 100) / 100

  const { data: storeCreditTxRaw } = await serviceClient
    .from('store_credit_transactions')
    .select('id, amount, type, description, order_item_id, created_at')
    .eq('user_id', id)
    .order('created_at', { ascending: false })
    .limit(100)

  const storeCreditTransactions = (storeCreditTxRaw ?? []).map((r) =>
    mapStoreCreditTransaction(r as unknown as Record<string, unknown>)
  )

  // 商家店员身份（merchant_staff）— 客服排查
  const { data: staffMemberships } = await serviceClient
    .from('merchant_staff')
    .select('id, merchant_id, user_id, role, nickname, is_active, created_at, merchants(name)')
    .eq('user_id', id)
    .order('created_at', { ascending: false })

  const staffRows: MerchantStaffAdminRowModel[] = (staffMemberships ?? []).map((s: Record<string, unknown>) => {
    const m = s.merchants as { name?: string } | { name?: string }[] | null | undefined
    const merchantName = Array.isArray(m) ? m[0]?.name : m?.name
    return {
      id: s.id as string,
      merchantId: s.merchant_id as string,
      userId: s.user_id as string,
      role: s.role as string,
      isActive: Boolean(s.is_active),
      nickname: (s.nickname as string | null) ?? null,
      email: userInfo.email,
      fullName: userInfo.full_name,
      createdAt: s.created_at as string,
      merchantName: merchantName ?? null,
    }
  })

  const emailForInvites = (authEmail || userInfo.email || '').trim().toLowerCase()
  let pendingInvitations: {
    id: string
    merchantId: string
    merchantName: string | null
    role: string
    expiresAt: string
    createdAt: string
  }[] = []

  if (emailForInvites.length > 0) {
    const { data: invRaw } = await serviceClient
      .from('staff_invitations')
      .select('id, merchant_id, role, expires_at, created_at, merchants(name)')
      .eq('invited_email', emailForInvites)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })

    pendingInvitations = (invRaw ?? []).map((r: Record<string, unknown>) => {
      const m = r.merchants as { name?: string } | { name?: string }[] | null | undefined
      const merchantName = Array.isArray(m) ? m[0]?.name : m?.name
      return {
        id: r.id as string,
        merchantId: r.merchant_id as string,
        merchantName: merchantName ?? null,
        role: r.role as string,
        expiresAt: r.expires_at as string,
        createdAt: r.created_at as string,
      }
    })
  }

  // 法律合规数据
  const consentStatus = await getUserConsentStatus(id)
  const { items: legalTimeline, total: legalTotal } = await getUserLegalTimeline(id, 1, 20)

  return (
    <div className="space-y-6">
      {/* 顶部导航 */}
      <Link href="/users" className="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700">
        ← Back to Users
      </Link>

      {/* 用 flex 双列，避免 grid 任意值 minmax(0,1fr) 中逗号导致 Tailwind 不生成样式、整页退化为单列 */}
      <div className="flex flex-col gap-5 md:flex-row md:items-start md:gap-6">
        {/* 主列：用户资料（订单/券在侧栏弹窗中查看） */}
        <div className="min-w-0 flex-1 space-y-6 order-1">
          {/* 用户信息卡片 */}
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <div className="flex items-start gap-4">
              {userInfo.avatar_url ? (
                <img src={userInfo.avatar_url} alt="" className="w-16 h-16 rounded-full object-cover border-2 border-gray-200 shrink-0" />
              ) : (
                <div className="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center text-2xl text-gray-400 shrink-0">
                  {(userInfo.full_name || userInfo.email)?.[0]?.toUpperCase() || '?'}
                </div>
              )}
              <div className="min-w-0 flex-1">
                <h1 className="text-xl font-bold text-gray-900">{userInfo.full_name || '—'}</h1>
                {isBanned && (
                  <span className="inline-block mt-2 px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">
                    Banned until {new Date(bannedUntil!).toLocaleDateString('en-US')}
                  </span>
                )}
              </div>
            </div>

            {/* 只读资料字段（管理员不可改邮箱/电话） */}
            <dl className="mt-6 grid gap-3 sm:grid-cols-2 text-sm border-t border-gray-100 pt-6">
              <div>
                <dt className="text-xs font-medium text-gray-500">Username</dt>
                <dd className="mt-0.5 text-gray-900 font-mono">{userInfo.username || '—'}</dd>
              </div>
              <div className="sm:col-span-2">
                <dt className="text-xs font-medium text-gray-500">Email</dt>
                <dd className="mt-0.5 text-gray-900 break-all">{hasEmail ? authEmail : (userInfo.email || '—')}</dd>
                <p className="text-xs text-gray-400 mt-1">Read-only for admins. Users change email in the app / support process.</p>
              </div>
              <div>
                <dt className="text-xs font-medium text-gray-500">Phone</dt>
                <dd className="mt-0.5 text-gray-900">{userInfo.phone || '—'}</dd>
                <p className="text-xs text-gray-400 mt-1">Read-only for admins.</p>
              </div>
              <div>
                <dt className="text-xs font-medium text-gray-500">User ID</dt>
                <dd className="mt-0.5 text-gray-600 font-mono text-xs break-all">{userInfo.id}</dd>
              </div>
              {userInfo.registration_source && (
                <div>
                  <dt className="text-xs font-medium text-gray-500">Registration source</dt>
                  <dd className="mt-0.5 text-gray-900">{userInfo.registration_source}</dd>
                </div>
              )}
              {userInfo.date_of_birth && (
                <div>
                  <dt className="text-xs font-medium text-gray-500">Date of Birth</dt>
                  <dd className="mt-0.5 text-gray-900">
                    {new Date(userInfo.date_of_birth + 'T00:00:00').toLocaleDateString('en-US')}
                    {(() => {
                      const dob = new Date(userInfo.date_of_birth + 'T00:00:00')
                      const age = Math.floor((Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000))
                      return <span className={`ml-2 text-xs px-1.5 py-0.5 rounded ${age < 18 ? 'bg-red-100 text-red-700' : 'bg-gray-100 text-gray-600'}`}>{age} yrs{age < 18 ? ' — Under 18' : ''}</span>
                    })()}
                  </dd>
                </div>
              )}
              {userInfo.last_login_at && (
                <div>
                  <dt className="text-xs font-medium text-gray-500">Last login</dt>
                  <dd className="mt-0.5 text-gray-900">{new Date(userInfo.last_login_at).toLocaleString('en-US')}</dd>
                </div>
              )}
            </dl>

            {oauthOnly && (
              <p className="mt-4 text-xs text-amber-700 bg-amber-50 border border-amber-100 rounded-lg px-3 py-2">
                This account may sign in with a social provider. Password reset / set password still apply if the user has an email on file.
              </p>
            )}

            {userInfo.bio && (
              <div className="mt-4 pt-4 border-t border-gray-100">
                <p className="text-xs font-medium text-gray-500">Bio</p>
                <p className="text-sm text-gray-700 mt-1 whitespace-pre-wrap">{userInfo.bio}</p>
              </div>
            )}

            {/* 日期信息 */}
            <div className="flex flex-wrap gap-4 mt-4 pt-4 border-t border-gray-100 text-xs text-gray-400">
              <span>Joined: {new Date(userInfo.created_at).toLocaleDateString('en-US')}</span>
              {userInfo.updated_at && <span>Profile updated: {new Date(userInfo.updated_at).toLocaleDateString('en-US')}</span>}
            </div>
          </div>

          <UserBillingAddressesPanel userId={id} addresses={billingAddresses} />

          <UserMerchantStaffSection
            staffRows={staffRows}
            pendingInvitations={pendingInvitations}
            userEmail={emailForInvites}
          />
        </div>

        {/* 右侧侧栏：固定宽度列，大屏贴顶 sticky */}
        <aside className="order-2 flex w-full shrink-0 flex-col gap-3 md:sticky md:top-4 md:w-72 md:max-w-[22rem] lg:w-80">
          <UserDetailSpendingAndActivityModal
            totalOrders={totalOrders}
            totalSpent={totalSpent}
            avgOrder={avgOrder}
            activeCoupons={activeCoupons}
            usedCoupons={usedCoupons}
            orders={orders ?? []}
            coupons={coupons ?? []}
          />

          <UserStoreCreditPanel
            userId={id}
            balance={storeCreditBalance}
            transactions={storeCreditTransactions}
          />

          <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-3">
            <h2 className="text-sm font-semibold text-gray-900">Role</h2>
            <p className="mt-0.5 text-xs text-gray-500">App role for this account.</p>
            <div className="mt-2">
              <RoleSelect userId={id} currentRole={userInfo.role} variant="panel" />
            </div>
          </div>

          <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-3">
            <h2 className="text-sm font-semibold text-gray-900">Password</h2>
            <div className="mt-2">
              <UserDetailPasswordPanel userId={id} hasEmail={hasEmail} />
            </div>
          </div>

          <div className="bg-white rounded-lg border border-red-200 shadow-sm p-3">
            <h2 className="text-sm font-semibold text-red-600">Account moderation</h2>
            <p className="mt-1 text-xs text-gray-600 leading-snug">
              Banning restricts sign-in. Use only when necessary.
            </p>
            <div className="mt-2">
              <BanUserButton userId={id} isBanned={!!isBanned} bannedUntil={bannedUntil ?? null} compact />
            </div>
          </div>
        </aside>
      </div>

      {/* ── Legal Compliance ── */}
      <div className="mt-10">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Legal Compliance</h2>
        <ConsentStatusCard items={consentStatus} />
        <div className="mt-6">
          <LegalTimeline userId={id} initialData={legalTimeline} totalCount={legalTotal} />
        </div>
      </div>
    </div>
  )
}

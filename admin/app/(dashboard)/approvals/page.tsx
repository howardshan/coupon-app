import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import ApprovalsPageClient from '@/components/approvals-page-client'
import { fetchPendingApprovalCounts } from '@/lib/admin-approval-counts'

export const dynamic = 'force-dynamic'

// ─── 每页条数 ───────────────────────────────────────────────────────────
const PER_PAGE = 20

// ─── SearchParams 类型 ──────────────────────────────────────────────────
type SearchParams = {
  tab?: string
  page?: string
  /** Merchants / Deals / Refund / After-Sales：pending=待办；history=已离开待办队列 */
  queue?: string
}

// ─── 数据类型定义 ────────────────────────────────────────────────────────

export type MerchantItem = {
  id: string
  name: string
  category: string | null
  contactName: string | null
  contactEmail: string | null
  phone: string | null
  createdAt: string
  status: string
  updatedAt: string | null
}

export type DealItem = {
  id: string
  title: string
  originalPrice: number
  discountPrice: number
  discountLabel: string | null
  imageUrls: string[]
  stockLimit: number | null
  expiresAt: string | null
  createdAt: string
  /** 供审批抽屉迷你时间线与详情页 builder 一致 */
  updatedAt: string | null
  publishedAt: string | null
  dealStatus: string | null
  isActive: boolean | null
  merchantName: string
  merchantAddress: string | null
  dishes: unknown
  packageContents: string | null
  usageNotes: string | null
  usageDays: string[] | null
  validityType: string | null
  validityDays: number | null
  maxPerPerson: number | null
  isStackable: boolean
  dealImages: { imageUrl: string; isPrimary: boolean }[]
}

export type RefundDisputeItem = {
  id: string
  refundAmount: number
  refundItems: unknown
  userReason: string
  merchantReason: string | null
  merchantDecidedAt: string | null
  /** merchant_decision: approved | rejected */
  merchantDecision: string | null
  createdAt: string
  updatedAt: string | null
  status: string
  adminDecision: string | null
  adminReason: string | null
  adminDecidedAt: string | null
  completedAt: string | null
  orderId: string
  merchantName: string
  userNameMasked: string
  /** 列表排序/「Resolved」展示：completed_at → admin_decided_at → updated_at */
  resolvedAt: string | null
}

export type AfterSalesItem = {
  id: string
  /** 关联订单，用于抽屉吸底跳转（视图含 order_id） */
  orderId: string
  status: string
  reasonCode: string
  reasonDetail: string
  refundAmount: number
  storeName: string | null
  /** 后台展示全名；与 user_id 对应 public.users */
  userFullName: string
  userId: string
  createdAt: string
  expiresAt: string | null
  /** 以下字段历史队列由视图提供，待办队列可为 null */
  refundedAt?: string | null
  platformDecidedAt?: string | null
  closedAt?: string | null
  resolvedAt?: string | null
}

export type StripeUnlinkItem = {
  id: string
  subjectType: 'merchant' | 'brand'
  subjectId: string
  merchantId: string
  merchantName: string
  brandName: string | null
  requestNote: string | null
  status: string
  createdAt: string
  updatedAt: string | null
  reviewedAt: string | null
  unbindAppliedAt: string | null
  rejectedReason: string | null
}

/** 平台售后历史：非待办状态（含 platform_approved 卡单） */
const AFTER_SALES_HISTORY_STATUSES = [
  'refunded',
  'platform_rejected',
  'platform_approved',
  'closed',
] as const

const MERCHANT_HISTORY_STATUSES = ['approved', 'rejected'] as const

/** 已离开「待审核」的 Deal（含下架） */
const DEAL_HISTORY_STATUSES = ['active', 'inactive', 'rejected'] as const

/** 管理员已裁定或流程终结（不含仍待商家/待用户升级的中间态） */
const REFUND_HISTORY_STATUSES = [
  'completed',
  'rejected_admin',
  'approved_admin',
  'cancelled',
] as const

function refundResolvedAtFromRow(r: Record<string, unknown>): string | null {
  const c = r.completed_at as string | null | undefined
  const a = r.admin_decided_at as string | null | undefined
  const u = r.updated_at as string | null | undefined
  return c ?? a ?? u ?? null
}

/** All Tab 列表行（全局时间序分页，与抽屉数据一致） */
export type UnifiedApprovalRow =
  | { kind: 'merchant'; data: MerchantItem }
  | { kind: 'deal'; data: DealItem }
  | { kind: 'refund'; data: RefundDisputeItem }
  | { kind: 'after-sales'; data: AfterSalesItem }
  | { kind: 'stripe-unlink'; data: StripeUnlinkItem }

// ─── 各 tab 数据查询 ─────────────────────────────────────────────────────

async function fetchMerchants(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number,
  queue: 'pending' | 'history',
) {
  const offset = (page - 1) * PER_PAGE
  let query = db
    .from('merchants')
    .select('id, name, category, contact_name, contact_email, phone, created_at, status, updated_at', {
      count: 'exact',
    })

  if (queue === 'pending') {
    query = query.eq('status', 'pending').order('created_at', { ascending: true })
  } else {
    query = query.in('status', [...MERCHANT_HISTORY_STATUSES]).order('updated_at', {
      ascending: false,
      nullsFirst: false,
    })
  }

  const { data, count } = await query.range(offset, offset + PER_PAGE - 1)

  const items: MerchantItem[] = (data ?? []).map((r: any) => ({
    id: r.id,
    name: r.name,
    category: r.category,
    contactName: r.contact_name,
    contactEmail: r.contact_email,
    phone: r.phone,
    createdAt: r.created_at,
    status: (r.status as string) ?? '',
    updatedAt: (r.updated_at as string | null) ?? null,
  }))
  return { items, total: count ?? 0 }
}

async function fetchDeals(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number,
  queue: 'pending' | 'history',
) {
  const offset = (page - 1) * PER_PAGE
  let query = db
    .from('deals')
    .select(
      `id, title, original_price, discount_price, discount_label,
       image_urls, stock_limit, expires_at, created_at, updated_at, published_at,
       deal_status, is_active,
       dishes, package_contents, usage_notes, usage_days,
       validity_type, validity_days, max_per_person, is_stackable,
       merchants(name, address),
       deal_images(image_url, is_primary)`,
      { count: 'exact' },
    )

  if (queue === 'pending') {
    query = query.eq('deal_status', 'pending').order('created_at', { ascending: true })
  } else {
    query = query.in('deal_status', [...DEAL_HISTORY_STATUSES]).order('updated_at', {
      ascending: false,
      nullsFirst: false,
    })
  }

  const { data, count } = await query.range(offset, offset + PER_PAGE - 1)

  const items: DealItem[] = (data ?? []).map((r: any) => ({
    id: r.id,
    title: r.title,
    originalPrice: r.original_price,
    discountPrice: r.discount_price,
    discountLabel: r.discount_label,
    imageUrls: r.image_urls ?? [],
    stockLimit: r.stock_limit,
    expiresAt: r.expires_at,
    createdAt: r.created_at,
    updatedAt: (r.updated_at as string | null) ?? null,
    publishedAt: (r.published_at as string | null) ?? null,
    dealStatus: (r.deal_status as string | null) ?? null,
    isActive: r.is_active != null ? Boolean(r.is_active) : null,
    merchantName: r.merchants?.name ?? '',
    merchantAddress: r.merchants?.address ?? null,
    dishes: r.dishes,
    packageContents: r.package_contents,
    usageNotes: r.usage_notes,
    usageDays: r.usage_days,
    validityType: r.validity_type,
    validityDays: r.validity_days,
    maxPerPerson: r.max_per_person,
    isStackable: r.is_stackable ?? false,
    dealImages: (r.deal_images ?? []).map((img: any) => ({
      imageUrl: img.image_url,
      isPrimary: img.is_primary,
    })),
  }))
  return { items, total: count ?? 0 }
}

function maskName(name: string | null) {
  if (!name) return 'User'
  if (name.length === 1) return `${name}*`
  return `${name[0]}***${name[name.length - 1]}`
}

async function fetchRefundDisputes(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number,
  queue: 'pending' | 'history',
) {
  const offset = (page - 1) * PER_PAGE
  let query = db
    .from('refund_requests')
    .select(
      `id, refund_amount, refund_items, user_reason,
       merchant_reason, merchant_decided_at, merchant_decision,
       created_at, updated_at, status,
       admin_decision, admin_reason, admin_decided_at, completed_at,
       order_id,
       merchants(name),
       users(full_name)`,
      { count: 'exact' },
    )

  if (queue === 'pending') {
    query = query.eq('status', 'pending_admin').order('created_at', { ascending: true })
  } else {
    query = query.in('status', [...REFUND_HISTORY_STATUSES]).order('updated_at', {
      ascending: false,
      nullsFirst: false,
    })
  }

  const { data, count } = await query.range(offset, offset + PER_PAGE - 1)

  const items: RefundDisputeItem[] = (data ?? []).map((r: any) => {
    const row = r as Record<string, unknown>
    return {
      id: r.id,
      refundAmount: Number(r.refund_amount ?? 0),
      refundItems: r.refund_items,
      userReason: r.user_reason,
      merchantReason: r.merchant_reason,
      merchantDecidedAt: r.merchant_decided_at,
      merchantDecision: r.merchant_decision ?? null,
      createdAt: r.created_at,
      updatedAt: r.updated_at ?? null,
      status: r.status ?? '',
      adminDecision: r.admin_decision ?? null,
      adminReason: r.admin_reason ?? null,
      adminDecidedAt: r.admin_decided_at ?? null,
      completedAt: r.completed_at ?? null,
      orderId: r.order_id,
      merchantName: r.merchants?.name ?? '',
      userNameMasked: maskName(r.users?.full_name ?? null),
      resolvedAt: refundResolvedAtFromRow(row),
    }
  })
  return { items, total: count ?? 0 }
}

const AFTER_SALES_LIST_SELECT =
  'id, order_id, status, reason_code, reason_detail, refund_amount, store_name, user_name, user_id, created_at, expires_at, refunded_at, platform_decided_at, closed_at, resolved_at'

function mapAfterSalesRow(r: Record<string, unknown>): AfterSalesItem {
  return {
    id: r.id as string,
    orderId: (r.order_id as string) ?? '',
    status: (r.status as string) ?? '',
    reasonCode: (r.reason_code as string) ?? '',
    reasonDetail: (r.reason_detail as string) ?? '',
    refundAmount: Number(r.refund_amount ?? 0),
    storeName: (r.store_name as string | null) ?? null,
    userFullName: (r.user_name as string) ?? '—',
    userId: (r.user_id as string) ?? '',
    createdAt: r.created_at as string,
    expiresAt: (r.expires_at as string | null) ?? null,
    refundedAt: (r.refunded_at as string | null) ?? null,
    platformDecidedAt: (r.platform_decided_at as string | null) ?? null,
    closedAt: (r.closed_at as string | null) ?? null,
    resolvedAt: (r.resolved_at as string | null) ?? null,
  }
}

async function fetchAfterSales(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number,
  queue: 'pending' | 'history',
) {
  const offset = (page - 1) * PER_PAGE
  let query = db
    .from('view_merchant_after_sales_requests')
    .select(AFTER_SALES_LIST_SELECT, { count: 'exact' })

  if (queue === 'pending') {
    query = query.eq('status', 'awaiting_platform').order('created_at', { ascending: true })
  } else {
    query = query.in('status', [...AFTER_SALES_HISTORY_STATUSES]).order('resolved_at', {
      ascending: false,
      nullsFirst: false,
    })
  }

  const { data, count } = await query.range(offset, offset + PER_PAGE - 1)

  const items: AfterSalesItem[] = (data ?? []).map((r) => mapAfterSalesRow(r as Record<string, unknown>))
  return { items, total: count ?? 0 }
}

const STRIPE_UNLINK_HISTORY_STATUSES = ['approved', 'rejected'] as const

const STRIPE_UNLINK_LIST_SELECT =
  'id, subject_type, subject_id, merchant_id, status, request_note, created_at, updated_at, reviewed_at, unbind_applied_at, rejected_reason'

/** 将 stripe_connect_unlink_requests 行映射为列表项（独立 Tab 与 All Tab 复用） */
async function stripeUnlinkRowsToItems(
  db: ReturnType<typeof getServiceRoleClient>,
  rows: Record<string, unknown>[],
): Promise<StripeUnlinkItem[]> {
  if (rows.length === 0) return []
  const mIds = [...new Set(rows.map((r) => r.merchant_id as string))]
  const bIds = [
    ...new Set(
      rows
        .filter((r) => r.subject_type === 'brand')
        .map((r) => r.subject_id as string),
    ),
  ]
  const { data: mrows } = mIds.length
    ? await db.from('merchants').select('id, name').in('id', mIds)
    : { data: [] as { id: string; name: string }[] }
  const { data: brows } = bIds.length
    ? await db.from('brands').select('id, name').in('id', bIds)
    : { data: [] as { id: string; name: string }[] }
  const mName = new Map((mrows ?? []).map((m) => [m.id, m.name as string]))
  const bName = new Map((brows ?? []).map((b) => [b.id, b.name as string]))
  return rows.map((r) => {
    const mid = r.merchant_id as string
    const st = r.subject_type as string
    const sid = r.subject_id as string
    return {
      id: r.id as string,
      subjectType: (st === 'brand' ? 'brand' : 'merchant') as 'merchant' | 'brand',
      subjectId: sid,
      merchantId: mid,
      merchantName: mName.get(mid) ?? '—',
      brandName: st === 'brand' ? (bName.get(sid) ?? null) : null,
      requestNote: (r.request_note as string | null) ?? null,
      status: (r.status as string) ?? '',
      createdAt: r.created_at as string,
      updatedAt: (r.updated_at as string | null) ?? null,
      reviewedAt: (r.reviewed_at as string | null) ?? null,
      unbindAppliedAt: (r.unbind_applied_at as string | null) ?? null,
      rejectedReason: (r.rejected_reason as string | null) ?? null,
    }
  })
}

async function fetchStripeUnlink(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number,
  queue: 'pending' | 'history',
) {
  const offset = (page - 1) * PER_PAGE
  let query = db
    .from('stripe_connect_unlink_requests')
    .select(STRIPE_UNLINK_LIST_SELECT, { count: 'exact' })

  if (queue === 'pending') {
    query = query.eq('status', 'pending').order('created_at', { ascending: true })
  } else {
    query = query
      .in('status', [...STRIPE_UNLINK_HISTORY_STATUSES])
      .order('reviewed_at', { ascending: false, nullsFirst: false })
  }

  const { data, count, error } = await query.range(offset, offset + PER_PAGE - 1)
  if (error) {
    throw new Error(error.message)
  }
  const rows = (data ?? []) as Record<string, unknown>[]
  const items = await stripeUnlinkRowsToItems(db, rows)
  return { items, total: count ?? 0 }
}

type RpcUnifiedPageRow = {
  approval_kind: string
  entity_id: string
  sort_at: string
}

/** All Tab：RPC 全局排序分页 + 按 id 批量拉取详情，保证顺序与数据库一致 */
async function fetchUnifiedAllTab(
  db: ReturnType<typeof getServiceRoleClient>,
  page: number
): Promise<{ rows: UnifiedApprovalRow[] }> {
  const offset = (page - 1) * PER_PAGE

  const { data: pageRaw, error: pageErr } = await db.rpc('admin_pending_approvals_unified_page', {
    p_limit: PER_PAGE,
    p_offset: offset,
  })
  if (pageErr) throw new Error(pageErr.message)

  const rpcRows = (pageRaw ?? []) as RpcUnifiedPageRow[]
  if (rpcRows.length === 0) {
    return { rows: [] }
  }

  const merchantIds = rpcRows.filter((r) => r.approval_kind === 'merchant').map((r) => r.entity_id)
  const dealIds = rpcRows.filter((r) => r.approval_kind === 'deal').map((r) => r.entity_id)
  const refundIds = rpcRows.filter((r) => r.approval_kind === 'refund_dispute').map((r) => r.entity_id)
  const afterSalesIds = rpcRows.filter((r) => r.approval_kind === 'after_sales').map((r) => r.entity_id)
  const stripeUnlinkIds = rpcRows.filter((r) => r.approval_kind === 'stripe_unlink').map((r) => r.entity_id)

  const [mRes, dRes, rRes, aRes, suRes] = await Promise.all([
    merchantIds.length
      ? db
          .from('merchants')
          .select('id, name, category, contact_name, contact_email, phone, created_at, status, updated_at')
          .in('id', merchantIds)
      : Promise.resolve({ data: [] as unknown[] }),
    dealIds.length
      ? db
          .from('deals')
          .select(
            `id, title, original_price, discount_price, discount_label,
             image_urls, stock_limit, expires_at, created_at, updated_at, published_at,
             deal_status, is_active,
             dishes, package_contents, usage_notes, usage_days,
             validity_type, validity_days, max_per_person, is_stackable,
             merchants(name, address),
             deal_images(image_url, is_primary)`
          )
          .in('id', dealIds)
      : Promise.resolve({ data: [] as unknown[] }),
    refundIds.length
      ? db
          .from('refund_requests')
          .select(
            `id, refund_amount, refund_items, user_reason,
             merchant_reason, merchant_decided_at, merchant_decision,
             created_at, updated_at, status,
             admin_decision, admin_reason, admin_decided_at, completed_at,
             order_id,
             merchants(name),
             users(full_name)`
          )
          .in('id', refundIds)
      : Promise.resolve({ data: [] as unknown[] }),
    afterSalesIds.length
      ? db
          .from('view_merchant_after_sales_requests')
          .select(AFTER_SALES_LIST_SELECT)
          .in('id', afterSalesIds)
      : Promise.resolve({ data: [] as unknown[] }),
    stripeUnlinkIds.length
      ? db.from('stripe_connect_unlink_requests').select(STRIPE_UNLINK_LIST_SELECT).in('id', stripeUnlinkIds)
      : Promise.resolve({ data: [] as unknown[] }),
  ])

  const merchantMap = new Map<string, MerchantItem>()
  for (const raw of mRes.data ?? []) {
    const r = raw as Record<string, unknown>
    const id = r.id as string
    merchantMap.set(id, {
      id,
      name: (r.name as string) ?? '',
      category: (r.category as string | null) ?? null,
      contactName: (r.contact_name as string | null) ?? null,
      contactEmail: (r.contact_email as string | null) ?? null,
      phone: (r.phone as string | null) ?? null,
      createdAt: r.created_at as string,
      status: (r.status as string) ?? 'pending',
      updatedAt: (r.updated_at as string | null) ?? null,
    })
  }

  const dealMap = new Map<string, DealItem>()
  for (const raw of dRes.data ?? []) {
    const r = raw as Record<string, unknown>
    const merchants = r.merchants as { name?: string; address?: string | null } | null
    const id = r.id as string
    dealMap.set(id, {
      id,
      title: (r.title as string) ?? '',
      originalPrice: Number(r.original_price ?? 0),
      discountPrice: Number(r.discount_price ?? 0),
      discountLabel: (r.discount_label as string | null) ?? null,
      imageUrls: (r.image_urls as string[]) ?? [],
      stockLimit: (r.stock_limit as number | null) ?? null,
      expiresAt: (r.expires_at as string | null) ?? null,
      createdAt: r.created_at as string,
      updatedAt: (r.updated_at as string | null) ?? null,
      publishedAt: (r.published_at as string | null) ?? null,
      dealStatus: (r.deal_status as string | null) ?? null,
      isActive: r.is_active != null ? Boolean(r.is_active) : null,
      merchantName: merchants?.name ?? '',
      merchantAddress: merchants?.address ?? null,
      dishes: r.dishes,
      packageContents: (r.package_contents as string | null) ?? null,
      usageNotes: (r.usage_notes as string | null) ?? null,
      usageDays: (r.usage_days as string[] | null) ?? null,
      validityType: (r.validity_type as string | null) ?? null,
      validityDays: (r.validity_days as number | null) ?? null,
      maxPerPerson: (r.max_per_person as number | null) ?? null,
      isStackable: Boolean(r.is_stackable),
      dealImages: ((r.deal_images as { image_url: string; is_primary: boolean }[]) ?? []).map((img) => ({
        imageUrl: img.image_url,
        isPrimary: img.is_primary,
      })),
    })
  }

  const refundMap = new Map<string, RefundDisputeItem>()
  for (const raw of rRes.data ?? []) {
    const r = raw as Record<string, unknown>
    const merchants = r.merchants as { name?: string } | null
    const users = r.users as { full_name?: string | null } | null
    const id = r.id as string
    refundMap.set(id, {
      id,
      refundAmount: Number(r.refund_amount ?? 0),
      refundItems: r.refund_items,
      userReason: (r.user_reason as string) ?? '',
      merchantReason: (r.merchant_reason as string | null) ?? null,
      merchantDecidedAt: (r.merchant_decided_at as string | null) ?? null,
      merchantDecision: (r.merchant_decision as string | null) ?? null,
      createdAt: r.created_at as string,
      updatedAt: (r.updated_at as string | null) ?? null,
      status: (r.status as string) ?? '',
      adminDecision: (r.admin_decision as string | null) ?? null,
      adminReason: (r.admin_reason as string | null) ?? null,
      adminDecidedAt: (r.admin_decided_at as string | null) ?? null,
      completedAt: (r.completed_at as string | null) ?? null,
      orderId: r.order_id as string,
      merchantName: merchants?.name ?? '',
      userNameMasked: maskName(users?.full_name ?? null),
      resolvedAt: refundResolvedAtFromRow(r),
    })
  }

  const afterMap = new Map<string, AfterSalesItem>()
  for (const raw of aRes.data ?? []) {
    const r = raw as Record<string, unknown>
    const id = r.id as string
    afterMap.set(id, mapAfterSalesRow(r))
  }

  const stripeItems = await stripeUnlinkRowsToItems(db, (suRes.data ?? []) as Record<string, unknown>[])
  const stripeMap = new Map(stripeItems.map((i) => [i.id, i]))

  const rows: UnifiedApprovalRow[] = []
  for (const pr of rpcRows) {
    switch (pr.approval_kind) {
      case 'merchant': {
        const data = merchantMap.get(pr.entity_id)
        if (data) rows.push({ kind: 'merchant', data })
        break
      }
      case 'deal': {
        const data = dealMap.get(pr.entity_id)
        if (data) rows.push({ kind: 'deal', data })
        break
      }
      case 'refund_dispute': {
        const data = refundMap.get(pr.entity_id)
        if (data) rows.push({ kind: 'refund', data })
        break
      }
      case 'after_sales': {
        const data = afterMap.get(pr.entity_id)
        if (data) rows.push({ kind: 'after-sales', data })
        break
      }
      case 'stripe_unlink': {
        const data = stripeMap.get(pr.entity_id)
        if (data) rows.push({ kind: 'stripe-unlink', data })
        break
      }
      default:
        break
    }
  }

  return { rows }
}

// ─── Page ────────────────────────────────────────────────────────────────

export default async function ApprovalsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'admin') redirect('/dashboard')

  const db = getServiceRoleClient()

  const tab = params.tab ?? 'all'
  const page = Math.max(1, parseInt(params.page ?? '1', 10) || 1)
  const approvalQueue: 'pending' | 'history' =
    params.queue === 'history' ? 'history' : 'pending'

  // 数量角标始终查询（用于 tab 角标显示）
  const counts = await fetchPendingApprovalCounts(db)

  // 根据当前 tab 查询对应数据
  let merchants: MerchantItem[] = []
  let merchantsTotal = 0
  let deals: DealItem[] = []
  let dealsTotal = 0
  let refundDisputes: RefundDisputeItem[] = []
  let refundDisputesTotal = 0
  let afterSales: AfterSalesItem[] = []
  let afterSalesTotal = 0
  let stripeUnlinks: StripeUnlinkItem[] = []
  let stripeUnlinkTotal = 0
  let unifiedAllRows: UnifiedApprovalRow[] = []

  if (tab === 'all') {
    const { rows } = await fetchUnifiedAllTab(db, page)
    unifiedAllRows = rows
  } else if (tab === 'merchants') {
    const res = await fetchMerchants(db, page, approvalQueue)
    merchants = res.items
    merchantsTotal = res.total
  } else if (tab === 'deals') {
    const res = await fetchDeals(db, page, approvalQueue)
    deals = res.items
    dealsTotal = res.total
  } else if (tab === 'refund-disputes') {
    const res = await fetchRefundDisputes(db, page, approvalQueue)
    refundDisputes = res.items
    refundDisputesTotal = res.total
  } else if (tab === 'after-sales') {
    const res = await fetchAfterSales(db, page, approvalQueue)
    afterSales = res.items
    afterSalesTotal = res.total
  } else if (tab === 'stripe-unlink') {
    const res = await fetchStripeUnlink(db, page, approvalQueue)
    stripeUnlinks = res.items
    stripeUnlinkTotal = res.total
  }

  return (
    <ApprovalsPageClient
      tab={tab}
      page={page}
      perPage={PER_PAGE}
      approvalQueue={approvalQueue}
      counts={counts}
      merchants={merchants}
      merchantsTotal={merchantsTotal}
      deals={deals}
      dealsTotal={dealsTotal}
      refundDisputes={refundDisputes}
      refundDisputesTotal={refundDisputesTotal}
      afterSales={afterSales}
      afterSalesTotal={afterSalesTotal}
      stripeUnlinks={stripeUnlinks}
      stripeUnlinkTotal={stripeUnlinkTotal}
      unifiedAllRows={unifiedAllRows}
    />
  )
}

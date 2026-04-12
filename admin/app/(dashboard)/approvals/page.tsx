import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import ApprovalsPageClient from '@/components/approvals-page-client'

export const dynamic = 'force-dynamic'

// ─── 每页条数 ───────────────────────────────────────────────────────────
const PER_PAGE = 20

// ─── SearchParams 类型 ──────────────────────────────────────────────────
type SearchParams = {
  tab?: string
  page?: string
  /** After-Sales：pending=待平台处理；history=已结案/平台已裁决（方案 A） */
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
}

export type AfterSalesItem = {
  id: string
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

/** 平台售后历史：非待办状态（含 platform_approved 卡单） */
const AFTER_SALES_HISTORY_STATUSES = [
  'refunded',
  'platform_rejected',
  'platform_approved',
  'closed',
] as const

/** All Tab 列表行（全局时间序分页，与抽屉数据一致） */
export type UnifiedApprovalRow =
  | { kind: 'merchant'; data: MerchantItem }
  | { kind: 'deal'; data: DealItem }
  | { kind: 'refund'; data: RefundDisputeItem }
  | { kind: 'after-sales'; data: AfterSalesItem }

// ─── 数量统计 ────────────────────────────────────────────────────────────
async function fetchCounts(db: ReturnType<typeof getServiceRoleClient>) {
  const [merchantRes, dealRes, refundRes, afterSalesRes] = await Promise.all([
    db.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    db.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
    db.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
    db.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
  ])
  return {
    merchants: merchantRes.count ?? 0,
    deals: dealRes.count ?? 0,
    refundDisputes: refundRes.count ?? 0,
    afterSales: afterSalesRes.count ?? 0,
  }
}

// ─── 各 tab 数据查询 ─────────────────────────────────────────────────────

async function fetchMerchants(db: ReturnType<typeof getServiceRoleClient>, page: number) {
  const offset = (page - 1) * PER_PAGE
  const { data, count } = await db
    .from('merchants')
    .select('id, name, category, contact_name, contact_email, phone, created_at', { count: 'exact' })
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .range(offset, offset + PER_PAGE - 1)

  const items: MerchantItem[] = (data ?? []).map((r: any) => ({
    id: r.id,
    name: r.name,
    category: r.category,
    contactName: r.contact_name,
    contactEmail: r.contact_email,
    phone: r.phone,
    createdAt: r.created_at,
  }))
  return { items, total: count ?? 0 }
}

async function fetchDeals(db: ReturnType<typeof getServiceRoleClient>, page: number) {
  const offset = (page - 1) * PER_PAGE
  const { data, count } = await db
    .from('deals')
    .select(
      `id, title, original_price, discount_price, discount_label,
       image_urls, stock_limit, expires_at, created_at, updated_at, published_at,
       deal_status, is_active,
       dishes, package_contents, usage_notes, usage_days,
       validity_type, validity_days, max_per_person, is_stackable,
       merchants(name, address),
       deal_images(image_url, is_primary)`,
      { count: 'exact' }
    )
    .eq('deal_status', 'pending')
    .order('created_at', { ascending: true })
    .range(offset, offset + PER_PAGE - 1)

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

async function fetchRefundDisputes(db: ReturnType<typeof getServiceRoleClient>, page: number) {
  const offset = (page - 1) * PER_PAGE
  const { data, count } = await db
    .from('refund_requests')
    .select(
      `id, refund_amount, refund_items, user_reason,
       merchant_reason, merchant_decided_at, merchant_decision,
       created_at, updated_at, status,
       admin_decision, admin_reason, admin_decided_at, completed_at,
       order_id,
       merchants(name),
       users(full_name)`,
      { count: 'exact' }
    )
    .eq('status', 'pending_admin')
    .order('created_at', { ascending: true })
    .range(offset, offset + PER_PAGE - 1)

  const items: RefundDisputeItem[] = (data ?? []).map((r: any) => ({
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
  }))
  return { items, total: count ?? 0 }
}

const AFTER_SALES_LIST_SELECT =
  'id, status, reason_code, reason_detail, refund_amount, store_name, user_name, user_id, created_at, expires_at, refunded_at, platform_decided_at, closed_at, resolved_at'

function mapAfterSalesRow(r: Record<string, unknown>): AfterSalesItem {
  return {
    id: r.id as string,
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

  const [mRes, dRes, rRes, aRes] = await Promise.all([
    merchantIds.length
      ? db
          .from('merchants')
          .select('id, name, category, contact_name, contact_email, phone, created_at')
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
    })
  }

  const afterMap = new Map<string, AfterSalesItem>()
  for (const raw of aRes.data ?? []) {
    const r = raw as Record<string, unknown>
    const id = r.id as string
    afterMap.set(id, mapAfterSalesRow(r))
  }

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
  const afterSalesQueue: 'pending' | 'history' =
    params.queue === 'history' ? 'history' : 'pending'

  // 数量角标始终查询（用于 tab 角标显示）
  const counts = await fetchCounts(db)

  // 根据当前 tab 查询对应数据
  let merchants: MerchantItem[] = []
  let merchantsTotal = 0
  let deals: DealItem[] = []
  let dealsTotal = 0
  let refundDisputes: RefundDisputeItem[] = []
  let refundDisputesTotal = 0
  let afterSales: AfterSalesItem[] = []
  let afterSalesTotal = 0
  let unifiedAllRows: UnifiedApprovalRow[] = []

  if (tab === 'all') {
    const { rows } = await fetchUnifiedAllTab(db, page)
    unifiedAllRows = rows
  } else if (tab === 'merchants') {
    const res = await fetchMerchants(db, page)
    merchants = res.items
    merchantsTotal = res.total
  } else if (tab === 'deals') {
    const res = await fetchDeals(db, page)
    deals = res.items
    dealsTotal = res.total
  } else if (tab === 'refund-disputes') {
    const res = await fetchRefundDisputes(db, page)
    refundDisputes = res.items
    refundDisputesTotal = res.total
  } else if (tab === 'after-sales') {
    const res = await fetchAfterSales(db, page, afterSalesQueue)
    afterSales = res.items
    afterSalesTotal = res.total
  }

  return (
    <ApprovalsPageClient
      tab={tab}
      page={page}
      perPage={PER_PAGE}
      afterSalesQueue={afterSalesQueue}
      counts={counts}
      merchants={merchants}
      merchantsTotal={merchantsTotal}
      deals={deals}
      dealsTotal={dealsTotal}
      refundDisputes={refundDisputes}
      refundDisputesTotal={refundDisputesTotal}
      afterSales={afterSales}
      afterSalesTotal={afterSalesTotal}
      unifiedAllRows={unifiedAllRows}
    />
  )
}

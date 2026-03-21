'use server'

import { createClient } from '@/lib/supabase/server'

const DEAL_SELECT = `
  id,
  title,
  discount_price,
  original_price,
  is_active,
  deal_status,
  expires_at,
  created_at,
  sort_order,
  applicable_merchant_ids,
  merchant_id,
  merchants(name, brand_id, brands(name))
`

const DEFAULT_LIMIT = 20
const MAX_LIMIT = 100

const MERCHANT_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const DEAL_STATUS_VALUES = ['pending', 'active', 'inactive', 'rejected'] as const
const STATUS_TOKEN_EXPIRED = 'expired'

function normalizeMerchantIdsForQuery(raw: string[] | undefined): string[] | null {
  if (!raw?.length) return null
  const out = raw.map((s) => s.trim()).filter((id) => MERCHANT_UUID_RE.test(id))
  return out.length ? out : null
}

function normalizeDealStatusTokens(raw: string[] | undefined): {
  dbStatuses: string[]
  includeExpired: boolean
} {
  if (!raw?.length) return { dbStatuses: [], includeExpired: false }
  const includeExpired = raw.includes(STATUS_TOKEN_EXPIRED)
  const dbStatuses = [
    ...new Set(
      raw.filter((x): x is (typeof DEAL_STATUS_VALUES)[number] =>
        (DEAL_STATUS_VALUES as readonly string[]).includes(x)
      )
    ),
  ]
  return { dbStatuses, includeExpired }
}

/** 降低 ilike 通配符被用户输入误用的风险 */
function escapeIlike(s: string) {
  return s.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_')
}

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return supabase
}

export type DealsListPayload = {
  deals: unknown[] | null
  totalCount: number
  merchantsForFilter: { id: string; name: string }[]
  fetchError: string | null
}

export type DealsListFilters = {
  q?: string
  merchantIds?: string[]
  /** pending | active | inactive | rejected | expired（过期按 expires_at） */
  statusTokens?: string[]
  dateFrom?: string
  dateTo?: string
  priceMin?: number
  priceMax?: number
  sort?: 'created_desc' | 'created_asc' | 'price_desc' | 'price_asc'
  page?: number
  limit?: number
}

/** 管理员 Deal 列表：搜索、状态/商家/日期/价格、排序、分页 */
export async function getDealsList(filters: DealsListFilters = {}): Promise<DealsListPayload> {
  const supabase = await requireAdmin()

  const q = filters.q?.trim() ?? ''
  const merchantIds = normalizeMerchantIdsForQuery(filters.merchantIds)
  const { dbStatuses, includeExpired } = normalizeDealStatusTokens(filters.statusTokens)
  const dateFrom = filters.dateFrom || null
  const dateTo = filters.dateTo || null
  const priceMin = filters.priceMin
  const priceMax = filters.priceMax
  const sort = filters.sort ?? 'created_desc'
  const page = Math.max(1, filters.page ?? 1)
  const limit = Math.min(MAX_LIMIT, Math.max(1, filters.limit ?? DEFAULT_LIMIT))
  const offset = (page - 1) * limit

  let query = supabase.from('deals').select(DEAL_SELECT, { count: 'exact' })

  if (q !== '') {
    const safe = escapeIlike(q)
    if (MERCHANT_UUID_RE.test(q)) {
      query = query.or(`id.eq.${q},title.ilike.%${safe}%`)
    } else {
      query = query.ilike('title', `%${safe}%`)
    }
  }

  if (merchantIds && merchantIds.length > 0) {
    query = query.in('merchant_id', merchantIds)
  }

  if (includeExpired || dbStatuses.length > 0) {
    const orParts: string[] = []
    for (const s of dbStatuses) {
      orParts.push(`deal_status.eq.${s}`)
    }
    if (includeExpired) {
      orParts.push(`expires_at.lt.${new Date().toISOString()}`)
    }
    query = query.or(orParts.join(','))
  }

  if (dateFrom) {
    query = query.gte('created_at', `${dateFrom}T00:00:00.000Z`)
  }
  if (dateTo) {
    query = query.lte('created_at', `${dateTo}T23:59:59.999Z`)
  }
  if (priceMin != null && Number.isFinite(priceMin)) {
    query = query.gte('discount_price', priceMin)
  }
  if (priceMax != null && Number.isFinite(priceMax)) {
    query = query.lte('discount_price', priceMax)
  }

  if (sort === 'price_asc' || sort === 'price_desc') {
    const asc = sort === 'price_asc'
    query = query.order('discount_price', { ascending: asc }).order('created_at', { ascending: false })
  } else {
    const asc = sort === 'created_asc'
    query = query.order('created_at', { ascending: asc })
  }

  query = query.range(offset, offset + limit - 1)

  const { data: deals, error, count } = await query

  const fetchError: string | null = error?.message ?? null
  const totalCount = count ?? 0

  const { data: merchantRows } = await supabase
    .from('merchants')
    .select('id, name')
    .order('name')
    .limit(800)

  return {
    deals: deals ?? null,
    totalCount,
    merchantsForFilter: merchantRows ?? [],
    fetchError,
  }
}

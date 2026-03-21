'use server'

import { createClient } from '@/lib/supabase/server'

const USER_SELECT = 'id, email, full_name, role, created_at, username'

const DEFAULT_LIMIT = 20
const MAX_LIMIT = 100

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const ALLOWED_ROLES = ['user', 'merchant', 'admin'] as const

function escapeIlike(s: string) {
  return s.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_')
}

function normalizeRoles(raw: string[] | undefined): string[] | null {
  if (!raw?.length) return null
  const out = [...new Set(raw.filter((r) => (ALLOWED_ROLES as readonly string[]).includes(r)))]
  return out.length ? out : null
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

export type UsersListPayload = {
  users: unknown[] | null
  totalCount: number
  fetchError: string | null
}

export type UsersListFilters = {
  q?: string
  roles?: string[]
  dateFrom?: string
  dateTo?: string
  sort?: 'created_desc' | 'created_asc' | 'email_asc' | 'email_desc' | 'name_asc' | 'name_desc'
  page?: number
  limit?: number
}

/** 管理员用户列表：关键词、角色多选、注册时间、排序、分页 */
export async function getUsersList(filters: UsersListFilters = {}): Promise<UsersListPayload> {
  const supabase = await requireAdmin()

  const q = filters.q?.trim() ?? ''
  const roles = normalizeRoles(filters.roles)
  const dateFrom = filters.dateFrom || null
  const dateTo = filters.dateTo || null
  const sort = filters.sort ?? 'created_desc'
  const page = Math.max(1, filters.page ?? 1)
  const limit = Math.min(MAX_LIMIT, Math.max(1, filters.limit ?? DEFAULT_LIMIT))
  const offset = (page - 1) * limit

  let query = supabase.from('users').select(USER_SELECT, { count: 'exact' })

  if (q !== '') {
    const safe = escapeIlike(q)
    if (UUID_RE.test(q)) {
      query = query.or(
        `id.eq.${q},email.ilike.%${safe}%,full_name.ilike.%${safe}%,username.ilike.%${safe}%`
      )
    } else {
      query = query.or(
        `email.ilike.%${safe}%,full_name.ilike.%${safe}%,username.ilike.%${safe}%`
      )
    }
  }

  if (roles && roles.length > 0) {
    query = query.in('role', roles)
  }

  if (dateFrom) {
    query = query.gte('created_at', `${dateFrom}T00:00:00.000Z`)
  }
  if (dateTo) {
    query = query.lte('created_at', `${dateTo}T23:59:59.999Z`)
  }

  switch (sort) {
    case 'email_asc':
      query = query.order('email', { ascending: true }).order('created_at', { ascending: false })
      break
    case 'email_desc':
      query = query.order('email', { ascending: false }).order('created_at', { ascending: false })
      break
    case 'name_asc':
      query = query.order('full_name', { ascending: true, nullsFirst: false }).order('created_at', { ascending: false })
      break
    case 'name_desc':
      query = query.order('full_name', { ascending: false, nullsFirst: false }).order('created_at', { ascending: false })
      break
    case 'created_asc':
      query = query.order('created_at', { ascending: true })
      break
    default:
      query = query.order('created_at', { ascending: false })
  }

  query = query.range(offset, offset + limit - 1)

  const { data: users, error, count } = await query

  const fetchError: string | null = error?.message ?? null
  const totalCount = count ?? 0

  return {
    users: users ?? null,
    totalCount,
    fetchError,
  }
}

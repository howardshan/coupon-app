'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { logMerchantActivityServer } from '@/lib/merchant-activity-events'
import {
  MERCHANT_STAFF_ROLES,
  type MerchantStaffRole,
} from '@/lib/merchant-staff-constants'

/** staff_invitations.role CHECK 仅允许三种；未注册用户只能发这三类邀请 */
const INVITABLE_ROLES_FOR_NEW_EMAIL = ['manager', 'cashier', 'service'] as const

function isMerchantStaffRole(s: string): s is MerchantStaffRole {
  return (MERCHANT_STAFF_ROLES as readonly string[]).includes(s)
}

async function requireAdminUserId(): Promise<string> {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase.from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return user.id
}

function revalidateStaffViews(merchantId: string, affectedUserId: string | null) {
  revalidatePath('/merchants')
  revalidatePath(`/merchants/${merchantId}`)
  revalidatePath('/users')
  if (affectedUserId) {
    revalidatePath(`/users/${affectedUserId}`)
  }
}

/**
 * 启用 / 禁用店员（与商家端软删语义一致：is_active）
 */
export async function setMerchantStaffActive(params: {
  staffId: string
  isActive: boolean
  merchantId: string
  affectedUserId: string
}) {
  const adminId = await requireAdminUserId()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchant_staff')
    .update({ is_active: params.isActive, updated_at: new Date().toISOString() })
    .eq('id', params.staffId)
    .eq('merchant_id', params.merchantId)

  if (error) throw new Error(error.message)

  await logMerchantActivityServer({
    merchantId: params.merchantId,
    eventType: 'admin_staff_status_changed',
    actorType: 'admin',
    actorUserId: adminId,
    detail: `staff_id=${params.staffId} user_id=${params.affectedUserId} is_active=${params.isActive}`,
  })

  revalidateStaffViews(params.merchantId, params.affectedUserId)
}

/**
 * 修改店员岗位
 */
export async function updateMerchantStaffRole(params: {
  staffId: string
  merchantId: string
  newRole: string
  affectedUserId: string
}) {
  const adminId = await requireAdminUserId()
  if (!isMerchantStaffRole(params.newRole)) {
    throw new Error(`Invalid role. Must be one of: ${MERCHANT_STAFF_ROLES.join(', ')}`)
  }

  const supabase = getServiceRoleClient()

  const { data: row, error: fetchErr } = await supabase
    .from('merchant_staff')
    .select('id, user_id, role')
    .eq('id', params.staffId)
    .eq('merchant_id', params.merchantId)
    .maybeSingle()

  if (fetchErr) throw new Error(fetchErr.message)
  if (!row) throw new Error('Staff record not found')

  const { data: merchant } = await supabase
    .from('merchants')
    .select('user_id')
    .eq('id', params.merchantId)
    .single()

  if (merchant && row.user_id === merchant.user_id) {
    throw new Error('Cannot change role for the store owner account')
  }

  const { error } = await supabase
    .from('merchant_staff')
    .update({ role: params.newRole, updated_at: new Date().toISOString() })
    .eq('id', params.staffId)
    .eq('merchant_id', params.merchantId)

  if (error) throw new Error(error.message)

  await logMerchantActivityServer({
    merchantId: params.merchantId,
    eventType: 'admin_staff_role_changed',
    actorType: 'admin',
    actorUserId: adminId,
    detail: `staff_id=${params.staffId} user_id=${row.user_id} ${row.role} -> ${params.newRole}`,
  })

  revalidateStaffViews(params.merchantId, params.affectedUserId)
}

/**
 * 清退店员（软删除：is_active = false）
 */
export async function removeMerchantStaff(params: {
  staffId: string
  merchantId: string
  affectedUserId: string
}) {
  const adminId = await requireAdminUserId()
  const supabase = getServiceRoleClient()

  const { data: row, error: fetchErr } = await supabase
    .from('merchant_staff')
    .select('id, user_id, role')
    .eq('id', params.staffId)
    .eq('merchant_id', params.merchantId)
    .maybeSingle()

  if (fetchErr) throw new Error(fetchErr.message)
  if (!row) throw new Error('Staff record not found')

  const { data: merchant } = await supabase
    .from('merchants')
    .select('user_id')
    .eq('id', params.merchantId)
    .single()

  if (merchant && row.user_id === merchant.user_id) {
    throw new Error('Cannot remove the store owner from staff list')
  }

  const { error } = await supabase
    .from('merchant_staff')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', params.staffId)
    .eq('merchant_id', params.merchantId)

  if (error) throw new Error(error.message)

  await logMerchantActivityServer({
    merchantId: params.merchantId,
    eventType: 'admin_staff_removed',
    actorType: 'admin',
    actorUserId: adminId,
    detail: `staff_id=${params.staffId} user_id=${row.user_id} role=${row.role} (soft remove)`,
  })

  revalidateStaffViews(params.merchantId, params.affectedUserId)
}

/**
 * 代商家邀请 / 添加店员：邮箱已注册则直接写入 merchant_staff；未注册则仅能对 manager/cashier/service 创建 pending 邀请。
 */
export async function inviteOrAddMerchantStaff(params: {
  merchantId: string
  email: string
  role: string
}) {
  const adminId = await requireAdminUserId()
  if (!isMerchantStaffRole(params.role)) {
    throw new Error(`Invalid role. Must be one of: ${MERCHANT_STAFF_ROLES.join(', ')}`)
  }

  const emailNorm = params.email.trim().toLowerCase()
  if (!emailNorm.includes('@')) throw new Error('Invalid email')

  const supabase = getServiceRoleClient()

  const { data: merchant, error: mErr } = await supabase
    .from('merchants')
    .select('id, user_id, name')
    .eq('id', params.merchantId)
    .maybeSingle()

  if (mErr) throw new Error(mErr.message)
  if (!merchant) throw new Error('Merchant not found')

  const { data: targetUser } = await supabase.from('users').select('id, email').eq('email', emailNorm).maybeSingle()

  if (targetUser) {
    if (targetUser.id === merchant.user_id) {
      throw new Error('This email belongs to the store owner — not added as staff')
    }

    const { data: existing } = await supabase
      .from('merchant_staff')
      .select('id')
      .eq('merchant_id', params.merchantId)
      .eq('user_id', targetUser.id)
      .maybeSingle()

    if (existing) {
      throw new Error('This user is already on staff for this store')
    }

    const { error: insErr } = await supabase.from('merchant_staff').insert({
      merchant_id: params.merchantId,
      user_id: targetUser.id,
      role: params.role,
      invited_by: adminId,
      is_active: true,
    })

    if (insErr) {
      if (insErr.code === '23505') throw new Error('This user is already on staff for this store')
      throw new Error(insErr.message)
    }

    await logMerchantActivityServer({
      merchantId: params.merchantId,
      eventType: 'admin_staff_invited',
      actorType: 'admin',
      actorUserId: adminId,
      detail: `direct add user_id=${targetUser.id} email=${emailNorm} role=${params.role}`,
    })

    revalidateStaffViews(params.merchantId, targetUser.id)
    return { ok: true as const, mode: 'added' as const }
  }

  // 未注册：仅允许邀请三种角色
  if (!(INVITABLE_ROLES_FOR_NEW_EMAIL as readonly string[]).includes(params.role)) {
    throw new Error(
      'For accounts that are not registered yet, only manager, cashier, or service invitations are allowed. ' +
        'Ask the user to sign up first, or choose one of those roles.'
    )
  }

  const { data: dupInv } = await supabase
    .from('staff_invitations')
    .select('id')
    .eq('merchant_id', params.merchantId)
    .eq('invited_email', emailNorm)
    .eq('status', 'pending')
    .maybeSingle()

  if (dupInv) {
    throw new Error('A pending invitation already exists for this email and store')
  }

  const { error: invErr } = await supabase.from('staff_invitations').insert({
    merchant_id: params.merchantId,
    invited_email: emailNorm,
    role: params.role,
    invited_by: adminId,
  })

  if (invErr) throw new Error(invErr.message)

  await logMerchantActivityServer({
    merchantId: params.merchantId,
    eventType: 'admin_staff_invited',
    actorType: 'admin',
    actorUserId: adminId,
    detail: `invitation pending email=${emailNorm} role=${params.role}`,
  })

  revalidateStaffViews(params.merchantId, null)
  return { ok: true as const, mode: 'invited' as const }
}

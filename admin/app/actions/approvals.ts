'use server'

import { revalidatePath, revalidateTag } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { APPROVALS_PENDING_COUNT_TAG } from '@/lib/approvals-cache-tag'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')

  // 返回 session token 供 Edge Function 使用
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) throw new Error('No active session')

  return session.access_token
}

// 管理员批准退款争议（调用 admin-refund Edge Function 执行实际退款）
export async function approveRefundDispute(requestId: string, adminReason?: string) {
  const token = await requireAdmin()

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!supabaseUrl) throw new Error('Supabase URL not configured')

  const res = await fetch(`${supabaseUrl}/functions/v1/admin-refund/${requestId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      action: 'approve',
      reason: adminReason?.trim() ?? '',
    }),
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error((body as { message?: string }).message ?? 'Failed to approve refund dispute')
  }

  revalidateTag(APPROVALS_PENDING_COUNT_TAG)
  revalidatePath('/approvals')
}

// 管理员最终拒绝退款争议（调用 admin-refund Edge Function，会发送 C14 邮件通知用户）
export async function rejectRefundDispute(requestId: string, adminReason: string) {
  const trimmedReason = adminReason.trim()
  if (trimmedReason.length < 10) {
    throw new Error('Rejection reason must be at least 10 characters')
  }

  const token = await requireAdmin()

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!supabaseUrl) throw new Error('Supabase URL not configured')

  const res = await fetch(`${supabaseUrl}/functions/v1/admin-refund/${requestId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      action: 'reject',
      reason: trimmedReason,
    }),
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error((body as { message?: string }).message ?? 'Failed to reject refund dispute')
  }

  revalidateTag(APPROVALS_PENDING_COUNT_TAG)
  revalidatePath('/approvals')
}

/** 客户端经 API 完成售后仲裁后调用，刷新 layout 角标缓存 */
export async function revalidateApprovalsPendingCount() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')

  revalidateTag(APPROVALS_PENDING_COUNT_TAG)
  revalidatePath('/approvals')
}

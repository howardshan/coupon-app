'use server'

import { revalidatePath, revalidateTag } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { sendAdminEmail } from '@/lib/email'
import { buildM20Email } from '@/lib/email-templates/merchant/stripe-unlink-approved'
import { buildM21Email } from '@/lib/email-templates/merchant/stripe-unlink-rejected'
import { applyPlatformStripeUnlink } from '@/lib/stripe-unlink-platform'
import { logMerchantActivityServer } from '@/lib/merchant-activity-events'
import { APPROVALS_PENDING_COUNT_TAG } from '@/lib/approvals-cache-tag'

async function requireAdminUserId(): Promise<string> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return user.id
}

/** 为 M20/M21 组收件人称呼与作用域说明 */
async function buildRecipientContext(
  admin: ReturnType<typeof getServiceRoleClient>,
  row: {
    subject_type: string
    subject_id: string
    merchant_id: string
    requested_by_user_id: string
  }
): Promise<{ addresseeName: string; toEmail: string; scopeLabel: string }> {
  const { data: u } = await admin
    .from('users')
    .select('email, full_name')
    .eq('id', row.requested_by_user_id)
    .maybeSingle()
  const toEmail = (u?.email as string | null)?.trim() ?? ''
  const addresseeName = ((u?.full_name as string | null)?.trim() || 'there').split(/\s+/)[0] || 'there'

  let scopeLabel: string
  if (row.subject_type === 'brand') {
    const { data: b } = await admin
      .from('brands')
      .select('name')
      .eq('id', row.subject_id)
      .maybeSingle()
    scopeLabel = b ? `Brand: ${String(b.name)}` : 'Brand'
  } else {
    const { data: m } = await admin
      .from('merchants')
      .select('name')
      .eq('id', row.merchant_id)
      .maybeSingle()
    scopeLabel = (m?.name as string) || 'This store'
  }
  return { addresseeName, toEmail, scopeLabel }
}

export async function approveStripeUnlinkRequest(requestId: string) {
  const adminId = await requireAdminUserId()
  const admin = getServiceRoleClient()
  const now = new Date().toISOString()

  const { data: row, error: fetchErr } = await admin
    .from('stripe_connect_unlink_requests')
    .select(
      'id, status, subject_type, subject_id, merchant_id, requested_by_user_id, unbind_applied_at, reviewed_by_admin_id'
    )
    .eq('id', requestId)
    .maybeSingle()
  if (fetchErr) throw new Error(fetchErr.message)
  if (!row) throw new Error('Request not found')

  if (row.status === 'approved' && row.unbind_applied_at) {
    revalidatePath('/approvals')
    revalidateTag(APPROVALS_PENDING_COUNT_TAG)
    return
  }
  if (row.status !== 'pending') {
    throw new Error('This request is no longer pending')
  }

  await applyPlatformStripeUnlink(admin, {
    subjectType: row.subject_type as 'merchant' | 'brand',
    subjectId:  row.subject_id,
    merchantId: row.merchant_id,
  })

  const { data: after, error: upErr } = await admin
    .from('stripe_connect_unlink_requests')
    .update({
      status:                 'approved',
      reviewed_by_admin_id:  adminId,
      reviewed_at:            now,
      unbind_applied_at:     now,
    })
    .eq('id', requestId)
    .eq('status', 'pending')
    .select('id')
    .maybeSingle()

  if (upErr) throw new Error(upErr.message)
  if (!after) {
    throw new Error('Could not finalize request (it may have been updated). Please refresh.')
  }

  const detail = `Stripe unbind approved. RequestId=${String(requestId).slice(0, 8)}…`
  await logMerchantActivityServer({
    merchantId: row.merchant_id,
    eventType:   'stripe_unlink_approved',
    actorType:   'admin',
    actorUserId:  adminId,
    detail:      detail,
  })

  try {
    const { addresseeName, toEmail, scopeLabel } = await buildRecipientContext(
      admin,
      row as { subject_type: string; subject_id: string; merchant_id: string; requested_by_user_id: string }
    )
    if (!toEmail) {
      console.warn('[approveStripeUnlink] no requester email, skip M20')
    } else {
    const { subject, html } = buildM20Email({
      addresseeName,
      requestId: row.id,
      scopeLabel,
      unboundAt: new Date(now).toLocaleString('en-US', { timeZone: 'America/Chicago' }),
    })
    await sendAdminEmail({
      to: toEmail,
      subject,
      htmlBody:   html,
      emailCode: 'M20',
      referenceId: row.id,
      recipientType: 'merchant',
    })
    }
  } catch (e) {
    console.error('[approveStripeUnlink] M20 email', e)
  }

  revalidatePath('/approvals')
  revalidatePath('/merchants')
  revalidatePath('/brands')
  revalidatePath(`/merchants/${row.merchant_id}`)
  if (row.subject_type === 'brand') {
    revalidatePath(`/brands/${row.subject_id}`)
  }
  revalidateTag(APPROVALS_PENDING_COUNT_TAG)
}

export async function rejectStripeUnlinkRequest(requestId: string, adminReason: string) {
  const trimmed = adminReason.trim()
  if (trimmed.length < 10) {
    throw new Error('Rejection reason must be at least 10 characters')
  }

  const adminId = await requireAdminUserId()
  const admin = getServiceRoleClient()
  const now = new Date().toISOString()

  const { data: row, error: fetchErr } = await admin
    .from('stripe_connect_unlink_requests')
    .select('id, status, subject_type, subject_id, merchant_id, requested_by_user_id, rejected_reason')
    .eq('id', requestId)
    .maybeSingle()
  if (fetchErr) throw new Error(fetchErr.message)
  if (!row) throw new Error('Request not found')

  if (row.status === 'rejected') {
    revalidatePath('/approvals')
    revalidateTag(APPROVALS_PENDING_COUNT_TAG)
    return
  }
  if (row.status !== 'pending') {
    throw new Error('This request is no longer pending')
  }

  const { error: upErr } = await admin
    .from('stripe_connect_unlink_requests')
    .update({
      status:                 'rejected',
      rejected_reason:         trimmed,
      reviewed_by_admin_id:   adminId,
      reviewed_at:             now,
    })
    .eq('id', requestId)
    .eq('status', 'pending')

  if (upErr) throw new Error(upErr.message)

  const detail = `Stripe unbind rejected. Reason: ${trimmed.slice(0, 200)}`
  await logMerchantActivityServer({
    merchantId: row.merchant_id,
    eventType:   'stripe_unlink_rejected',
    actorType:   'admin',
    actorUserId:  adminId,
    detail:      detail,
  })

  try {
    const { addresseeName, toEmail, scopeLabel } = await buildRecipientContext(
      admin,
      row as { subject_type: string; subject_id: string; merchant_id: string; requested_by_user_id: string }
    )
    if (!toEmail) {
      console.warn('[rejectStripeUnlink] no requester email, skip M21')
    } else {
    const { subject, html } = buildM21Email({
      addresseeName,
      requestId: row.id,
      scopeLabel,
      adminReason: trimmed,
    })
    await sendAdminEmail({
      to: toEmail,
      subject,
      htmlBody:   html,
      emailCode: 'M21',
      referenceId: row.id,
      recipientType: 'merchant',
    })
    }
  } catch (e) {
    console.error('[rejectStripeUnlink] M21 email', e)
  }

  revalidatePath('/approvals')
  revalidatePath(`/merchants/${row.merchant_id}`)
  revalidateTag(APPROVALS_PENDING_COUNT_TAG)
}

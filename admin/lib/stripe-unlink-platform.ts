/**
 * 仅平台库解绑 Stripe Connect（v1 不调 Stripe 销户）
 * 与 deal_joy/supabase/functions/merchant-withdrawal 中清空 stale 字段的口径一致。
 * 注意：在 Server Action 内由 service_role 调用。
 */

import type { SupabaseClient } from '@supabase/supabase-js'

export type StripeUnlinkSubject = {
  subjectType: 'merchant' | 'brand'
  subjectId: string
  /** 申请行冗余的门店，用于解绑后 bank 行清理的锚点 */
  merchantId: string
}

export async function applyPlatformStripeUnlink(
  admin: SupabaseClient,
  sub: StripeUnlinkSubject
): Promise<void> {
  if (sub.subjectType === 'merchant') {
    if (sub.subjectId !== sub.merchantId) {
      throw new Error('Invalid merchant subject for unlink')
    }
    const { error: u1 } = await admin
      .from('merchants')
      .update({
        stripe_account_id:     null,
        stripe_account_status: 'not_connected',
        stripe_account_email:  null,
      })
      .eq('id', sub.merchantId)
    if (u1) throw new Error(`Failed to clear merchant Stripe: ${u1.message}`)

    const { error: d1 } = await admin
      .from('merchant_bank_accounts')
      .delete()
      .eq('merchant_id', sub.merchantId)
    if (d1) throw new Error(`Failed to clear bank accounts: ${d1.message}`)
    return
  }

  // brand
  const { data: b, error: bErr } = await admin
    .from('brands')
    .select('id')
    .eq('id', sub.subjectId)
    .maybeSingle()
  if (bErr || !b) throw new Error('Brand not found for unlink')

  const { error: u2 } = await admin
    .from('brands')
    .update({
      stripe_account_id:     null,
      stripe_account_status: 'not_connected',
      stripe_account_email:  null,
    })
    .eq('id', sub.subjectId)
  if (u2) throw new Error(`Failed to clear brand Stripe: ${u2.message}`)

  // 子门店若仍有残留 Connect 展示字段，一并置空
  const { error: u3 } = await admin
    .from('merchants')
    .update({
      stripe_account_id:     null,
      stripe_account_status: 'not_connected',
      stripe_account_email:  null,
    })
    .eq('brand_id', sub.subjectId)
  if (u3) throw new Error(`Failed to clear brand stores: ${u3.message}`)

  // 清品牌下各店银行账户缓存行
  const { data: stores, error: sErr } = await admin
    .from('merchants')
    .select('id')
    .eq('brand_id', sub.subjectId)
  if (sErr) throw new Error(`Failed to list brand stores: ${sErr.message}`)

  for (const row of stores ?? []) {
    const mid = (row as { id: string }).id
    const { error: d2 } = await admin.from('merchant_bank_accounts').delete().eq('merchant_id', mid)
    if (d2) throw new Error(`Failed to clear bank for store ${mid}: ${d2.message}`)
  }
}

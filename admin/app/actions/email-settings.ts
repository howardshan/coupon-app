'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

// 权限校验：仅 admin 可操作
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
  return user
}

// 切换邮件类型的全局开关（开 → 关 / 关 → 开）
export async function toggleEmailGlobalEnabled(emailCode: string, enabled: boolean) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('email_type_settings')
    .update({
      global_enabled: enabled,
      updated_at: new Date().toISOString(),
      updated_by: user.id,
    })
    .eq('email_code', emailCode)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/email-types')
}

// 更新 A 系列邮件的管理员收件人列表
export async function updateAdminRecipients(emailCode: string, emails: string[]) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  // 过滤格式合法的邮箱
  const validEmails = emails
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e.includes('@') && e.includes('.'))

  const { error } = await supabase
    .from('email_type_settings')
    .update({
      admin_recipient_emails: validEmails,
      updated_at: new Date().toISOString(),
      updated_by: user.id,
    })
    .eq('email_code', emailCode)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/email-types')
}

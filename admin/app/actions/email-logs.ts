'use server'

import { createClient } from '@/lib/supabase/server'

// 权限校验：仅 admin 可读取邮件日志正文
async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') return null
  return supabase
}

/** 管理端预览：按 id 拉取 HTML 正文（列表接口不返回 html_body 以减轻负载） */
export async function getEmailLogHtmlBody(logId: string) {
  const supabase = await requireAdmin()
  if (!supabase) return { error: 'Forbidden' as const }

  const { data, error } = await supabase
    .from('email_logs')
    .select('id, subject, html_body')
    .eq('id', logId)
    .single()

  if (error) return { error: error.message }
  return {
    subject: data.subject as string,
    htmlBody: (data.html_body as string | null) ?? '',
  }
}

// =============================================================
// DealJoy 邮件发送工具（Admin Next.js Server Actions 专用）
// Admin 端触发的邮件（M3/M4/M16/A 系列等）通过此模块发送
// 与 Edge Function 的 _shared/email.ts 共享相同的发送逻辑
// =============================================================

import { SupabaseClient } from '@supabase/supabase-js'
import { getServiceRoleClient } from '@/lib/supabase/service'

const SMTP2GO_API_URL = 'https://api.smtp2go.com/v3/email/send'
const FROM_NAME       = 'CrunchyPlum'
const FROM_EMAIL      = 'noreply@crunchyplum.com'

// ─────────────────────────────────────────────────────────────
// 类型定义
// ─────────────────────────────────────────────────────────────

export interface AdminEmailPayload {
  /** 收件人邮箱（单个或多个） */
  to: string | string[]
  /** 邮件主题 */
  subject: string
  /** HTML 正文（同时写入 email_logs 供管理端预览） */
  htmlBody: string
  /** 纯文本正文（可选） */
  textBody?: string
  /** 邮件类型编码，对应 email_type_settings.email_code */
  emailCode: string
  /** 关联业务 ID，用于幂等性检查 */
  referenceId?: string
  /** 收件人类型 */
  recipientType: 'customer' | 'merchant' | 'admin'
}

// ─────────────────────────────────────────────────────────────
// 主函数：sendAdminEmail
// Admin Server Action 调用入口，内部自动使用 service_role client
// ─────────────────────────────────────────────────────────────

export async function sendAdminEmail(payload: AdminEmailPayload): Promise<void> {
  const supabase = getServiceRoleClient()
  await _sendEmailWithClient(supabase, payload)
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：查询管理员收件人列表
// 用于 A 系列邮件，收件人从 email_type_settings.admin_recipient_emails 读取
// ─────────────────────────────────────────────────────────────

export async function getAdminRecipients(emailCode: string): Promise<string[]> {
  const supabase = getServiceRoleClient()

  const { data } = await supabase
    .from('email_type_settings')
    .select('admin_recipient_emails')
    .eq('email_code', emailCode)
    .single()

  if (!data?.admin_recipient_emails) return []

  const emails = data.admin_recipient_emails as string[]
  return emails.filter((e) => typeof e === 'string' && e.includes('@'))
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：检查某邮件类型的全局开关是否开启
// ─────────────────────────────────────────────────────────────

export async function isEmailEnabled(emailCode: string): Promise<boolean> {
  const supabase = getServiceRoleClient()

  const { data } = await supabase
    .from('email_type_settings')
    .select('global_enabled')
    .eq('email_code', emailCode)
    .single()

  return data?.global_enabled === true
}

// ─────────────────────────────────────────────────────────────
// 内部函数：_sendEmailWithClient
// 四步发送权限链（全局开关→幂等→发送→日志），Admin 端无用户偏好检查
// ─────────────────────────────────────────────────────────────

async function _sendEmailWithClient(
  supabase: SupabaseClient,
  payload: AdminEmailPayload
): Promise<void> {
  try {
    // ① 全局开关检查
    const { data: setting } = await supabase
      .from('email_type_settings')
      .select('global_enabled')
      .eq('email_code', payload.emailCode)
      .single()

    if (!setting?.global_enabled) return

    const apiKey = process.env.SMTP2GO_API_KEY
    if (!apiKey) {
      console.error('[admin-email] SMTP2GO_API_KEY not set')
      return
    }

    const recipients = Array.isArray(payload.to) ? payload.to : [payload.to]

    for (const recipientEmail of recipients) {
      // ② 幂等性检查（Admin 端邮件无用户偏好，直接进行幂等检查）
      if (payload.referenceId) {
        const cutoff = new Date(Date.now() - 86_400_000).toISOString()
        const { data: existing } = await supabase
          .from('email_logs')
          .select('id')
          .eq('email_code', payload.emailCode)
          .eq('reference_id', payload.referenceId)
          .eq('recipient_email', recipientEmail)
          .eq('status', 'sent')
          .gte('created_at', cutoff)
          .maybeSingle()

        if (existing) continue
      }

      // ③-a 写入 pending 日志
      const { data: logRow, error: logInsertError } = await supabase
        .from('email_logs')
        .insert({
          recipient_email: recipientEmail,
          recipient_type: payload.recipientType,
          email_code: payload.emailCode,
          reference_id: payload.referenceId ?? null,
          subject: payload.subject,
          html_body: payload.htmlBody,
          status: 'pending',
        })
        .select('id')
        .single()

      if (logInsertError) {
        console.error('[admin-email] Failed to insert email_log:', logInsertError)
        continue
      }

      const logId = logRow?.id

      // ③-b 调用 SMTP2GO REST API
      let smtp2goMessageId: string | null = null
      let errorMessage: string | null = null
      let success = false

      try {
        const res = await fetch(SMTP2GO_API_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            api_key: apiKey,
            to: [recipientEmail],
            sender: `${FROM_NAME} <${FROM_EMAIL}>`,
            subject: payload.subject,
            html_body: payload.htmlBody,
            ...(payload.textBody ? { text_body: payload.textBody } : {}),
          }),
        })

        const data = await res.json()

        if (res.ok && data?.data?.succeeded === 1) {
          smtp2goMessageId = data?.data?.email_id ?? null
          success = true
        } else {
          errorMessage = JSON.stringify(data?.data ?? data)
        }
      } catch (fetchErr) {
        errorMessage = String(fetchErr)
      }

      // ③-c 更新日志状态
      if (logId) {
        await supabase
          .from('email_logs')
          .update({
            status: success ? 'sent' : 'failed',
            smtp2go_message_id: smtp2goMessageId,
            error_message: errorMessage,
            sent_at: success ? new Date().toISOString() : null,
          })
          .eq('id', logId)
      }

      if (!success) {
        console.error(`[admin-email] Failed to send ${payload.emailCode} to ${recipientEmail}:`, errorMessage)
      }
    }
  } catch (err) {
    // 顶层 catch：邮件发送失败不得影响核心业务流程
    console.error('[admin-email] Unexpected error in sendAdminEmail:', err)
  }
}

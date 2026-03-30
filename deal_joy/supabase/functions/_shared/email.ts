// =============================================================
// Crunchy Plum 邮件发送工具（Edge Functions 专用）
// 所有 Edge Function 通过此模块统一发送邮件
//
// 发送前依次经过四步检查：
//   ① 全局开关检查（email_type_settings.global_enabled）
//   ② 用户/商家偏好检查（仅 user_configurable = true 时）
//   ③ 幂等性检查（24h 内不重复发送）
//   ④ 调用 SMTP2GO API + 写入 email_logs
// =============================================================

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// SMTP2GO 配置
const SMTP2GO_API_URL = "https://api.smtp2go.com/v3/email/send";
const FROM_NAME       = "CrunchyPlum";
const FROM_EMAIL      = "noreply@crunchyplum.com";

// ─────────────────────────────────────────────────────────────
// 类型定义
// ─────────────────────────────────────────────────────────────

export interface EmailPayload {
  /** 收件人邮箱（单个或多个） */
  to: string | string[];
  /** 邮件主题 */
  subject: string;
  /** HTML 正文（同时用于 email_logs 存档） */
  htmlBody: string;
  /** 纯文本正文（可选，作为 HTML 的降级版本） */
  textBody?: string;
  /** 邮件类型编码，对应 email_type_settings.email_code（如 'C2'） */
  emailCode: string;
  /** 关联业务 ID（UUID），用于幂等性去重 */
  referenceId?: string;
  /** 收件人类型 */
  recipientType: "customer" | "merchant" | "admin";
  /** 客户端邮件：传 user_id，用于偏好检查 */
  userId?: string;
  /** 商家端邮件：传 merchant_id，用于偏好检查 */
  merchantId?: string;
}

// ─────────────────────────────────────────────────────────────
// 主函数：sendEmail
// 失败时只记录日志，不向上抛出异常（即发即忘模式）
// ─────────────────────────────────────────────────────────────

export async function sendEmail(
  supabaseClient: SupabaseClient,
  payload: EmailPayload
): Promise<void> {
  try {
    // ① 全局开关检查
    const { data: setting } = await supabaseClient
      .from("email_type_settings")
      .select("global_enabled, user_configurable")
      .eq("email_code", payload.emailCode)
      .single();

    if (!setting?.global_enabled) {
      // 全局已关闭，直接终止，不记录日志
      return;
    }

    const apiKey = Deno.env.get("SMTP2GO_API_KEY");
    if (!apiKey) {
      console.error("[email] SMTP2GO_API_KEY not set");
      return;
    }

    const recipients = Array.isArray(payload.to) ? payload.to : [payload.to];

    for (const recipientEmail of recipients) {
      // ② 用户/商家偏好检查（仅 user_configurable = true 时适用）
      if (setting.user_configurable) {
        if (payload.userId) {
          const { data: pref } = await supabaseClient
            .from("user_email_preferences")
            .select("enabled")
            .eq("user_id", payload.userId)
            .eq("email_code", payload.emailCode)
            .maybeSingle();

          // 有明确记录且为 false 时才跳过；无记录则默认发送
          if (pref !== null && !pref.enabled) continue;
        }

        if (payload.merchantId) {
          const { data: pref } = await supabaseClient
            .from("merchant_email_preferences")
            .select("enabled")
            .eq("merchant_id", payload.merchantId)
            .eq("email_code", payload.emailCode)
            .maybeSingle();

          if (pref !== null && !pref.enabled) continue;
        }
      }

      // ③ 幂等性检查：24 小时内是否已成功发过同类邮件
      if (payload.referenceId) {
        const cutoff = new Date(Date.now() - 86_400_000).toISOString();
        const { data: existing } = await supabaseClient
          .from("email_logs")
          .select("id")
          .eq("email_code", payload.emailCode)
          .eq("reference_id", payload.referenceId)
          .eq("recipient_email", recipientEmail)
          .eq("status", "sent")
          .gte("created_at", cutoff)
          .maybeSingle();

        if (existing) continue; // 已发过，跳过
      }

      // ④-a 写入 pending 日志（含 html_body 供管理端预览）
      const { data: logRow, error: logInsertError } = await supabaseClient
        .from("email_logs")
        .insert({
          recipient_email: recipientEmail,
          recipient_type: payload.recipientType,
          email_code: payload.emailCode,
          reference_id: payload.referenceId ?? null,
          subject: payload.subject,
          html_body: payload.htmlBody,
          status: "pending",
        })
        .select("id")
        .single();

      if (logInsertError) {
        console.error("[email] Failed to insert email_log:", logInsertError);
        continue;
      }

      const logId = logRow?.id;

      // ④-b 调用 SMTP2GO REST API
      let smtp2goMessageId: string | null = null;
      let errorMessage: string | null = null;
      let success = false;

      try {
        const res = await fetch(SMTP2GO_API_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            api_key: apiKey,
            to: [recipientEmail],
            sender: `${FROM_NAME} <${FROM_EMAIL}>`,
            subject: payload.subject,
            html_body: payload.htmlBody,
            ...(payload.textBody ? { text_body: payload.textBody } : {}),
          }),
        });

        const data = await res.json();

        if (res.ok && data?.data?.succeeded === 1) {
          smtp2goMessageId = data?.data?.email_id ?? null;
          success = true;
        } else {
          errorMessage = JSON.stringify(data?.data ?? data);
        }
      } catch (fetchErr) {
        errorMessage = String(fetchErr);
      }

      // ④-c 更新日志状态
      if (logId) {
        await supabaseClient
          .from("email_logs")
          .update({
            status: success ? "sent" : "failed",
            smtp2go_message_id: smtp2goMessageId,
            error_message: errorMessage,
            sent_at: success ? new Date().toISOString() : null,
          })
          .eq("id", logId);
      }

      if (!success) {
        console.error(`[email] Failed to send ${payload.emailCode} to ${recipientEmail}:`, errorMessage);
      }
    }
  } catch (err) {
    // 顶层 catch：邮件发送失败不得影响核心业务流程
    console.error("[email] Unexpected error in sendEmail:", err);
  }
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：查询管理员收件人列表
// 用于 A 系列邮件（从 email_type_settings.admin_recipient_emails 读取）
// ─────────────────────────────────────────────────────────────

export async function getAdminRecipients(
  supabaseClient: SupabaseClient,
  emailCode: string
): Promise<string[]> {
  const { data } = await supabaseClient
    .from("email_type_settings")
    .select("admin_recipient_emails")
    .eq("email_code", emailCode)
    .single();

  if (!data?.admin_recipient_emails) return [];

  const emails = data.admin_recipient_emails as string[];
  return emails.filter((e) => typeof e === "string" && e.includes("@"));
}

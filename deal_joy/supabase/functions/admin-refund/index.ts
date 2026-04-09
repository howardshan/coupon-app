// Edge Function: admin-refund
// 管理员仲裁接口 — 处理商家拒绝后升级的退款申请
// GET  /admin-refund?status=pending_admin&page=1&per_page=20  — 列出待仲裁申请
// PATCH /admin-refund/:id                                     — 批准或拒绝

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { sendEmail } from '../_shared/email.ts';
import { buildC14Email } from '../_shared/email-templates/customer/admin-refund-rejected.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, PATCH, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(message: string, code: string, status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (!['GET', 'PATCH'].includes(req.method)) {
    return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

    // 提取 JWT
    const url = new URL(req.url);
    const bodyRaw = req.method !== 'GET' ? await req.json().catch(() => ({})) : {};
    const body = bodyRaw as Record<string, unknown>;
    const queryToken = url.searchParams.get('access_token')?.trim() ?? '';
    const bodyToken = (body.access_token != null ? String(body.access_token).trim() : '');
    const authHeader = req.headers.get('Authorization') ?? '';
    const headerToken = authHeader.replace(/^\s*Bearer\s+/i, '').trim();
    const token = bodyToken || queryToken || headerToken;

    if (!token) {
      return errorResponse('Missing authorization', 'unauthorized', 401);
    }

    // 验证 JWT
    const userClient = createClient(supabaseUrl, anonKey);
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData?.user) {
      return errorResponse('Invalid or expired token', 'unauthorized', 401);
    }
    const userId = userData.user.id;

    // 验证管理员权限（检查 users 表的 role 字段）
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: userProfile } = await serviceClient
      .from('users')
      .select('role')
      .eq('id', userId)
      .maybeSingle();

    if (!userProfile || (userProfile.role !== 'admin' && userProfile.role !== 'super_admin')) {
      return errorResponse('Admin access required', 'forbidden', 403);
    }

    // 解析路径，提取 refundRequestId（若有）
    const pathname = url.pathname;
    const match = pathname.match(/\/admin-refund\/?(.*)$/);
    const suffix = match ? match[1].replace(/^\/|\/$/g, '') : '';
    const refundRequestId = suffix || null;

    // ── GET：列出退款申请 ──────────────────────────────────
    if (req.method === 'GET') {
      const statusFilter = url.searchParams.get('status') ?? 'pending_admin';
      const page = Math.max(parseInt(url.searchParams.get('page') ?? '1', 10), 1);
      const perPage = Math.min(Math.max(parseInt(url.searchParams.get('per_page') ?? '20', 10), 1), 100);
      const offset = (page - 1) * perPage;

      let query = serviceClient
        .from('refund_requests')
        .select(`
          id, status, refund_amount, reason, user_reason,
          merchant_reason, merchant_decided_at, merchant_decision,
          admin_reason, admin_decided_at, admin_decision,
          created_at, updated_at, order_item_id,
          orders!inner(
            id, order_number, total_amount, status, created_at,
            deals!inner(id, title),
            merchants!inner(id, name)
          )
        `, { count: 'exact' });

      if (statusFilter !== 'all') {
        query = query.eq('status', statusFilter);
      }

      const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(offset, offset + perPage - 1);

      if (error) {
        console.error('[admin-refund] list error:', error);
        return errorResponse('Failed to fetch refund requests', 'db_error', 500);
      }

      // 管理端若仍读旧字段名，在此做别名
      const rows = (data ?? []).map((row: Record<string, unknown>) => ({
        ...row,
        merchant_response: row.merchant_reason ?? null,
        admin_response: row.admin_reason ?? null,
        responded_at: row.merchant_decided_at ?? null,
      }));

      return jsonResponse({
        data: rows,
        total: count ?? 0,
        page,
        per_page: perPage,
        has_more: (count ?? 0) > offset + perPage,
      });
    }

    // ── PATCH：审批退款申请 ──────────────────────────────────
    if (!refundRequestId) {
      return errorResponse('refundRequestId is required in path', 'bad_request', 400);
    }

    const { action, reason: adminReason } = body as { action?: string; reason?: string };
    if (!action || !['approve', 'reject'].includes(action)) {
      return errorResponse("action must be 'approve' or 'reject'", 'invalid_action', 400);
    }
    if (action === 'reject' && (!adminReason || adminReason.trim().length < 10)) {
      return errorResponse('Rejection reason must be at least 10 characters', 'invalid_reason', 400);
    }

    // 查询申请，确认状态为 pending_admin（含退款金额、关联订单信息用于发邮件）
    const { data: refundReq, error: rrError } = await serviceClient
      .from('refund_requests')
      .select('id, status, order_id, order_item_id, refund_amount, user_id, orders!inner(order_number)')
      .eq('id', refundRequestId)
      .single();

    if (rrError || !refundReq) {
      return errorResponse('Refund request not found', 'not_found', 404);
    }
    if (refundReq.status !== 'pending_admin') {
      return errorResponse(
        `Refund request status is '${refundReq.status}', expected 'pending_admin'`,
        'invalid_status',
        400,
      );
    }

    const now = new Date().toISOString();

    if (action === 'approve') {
      // 调用 execute-refund 执行实际退款
      const executeUrl = `${supabaseUrl}/functions/v1/execute-refund`;
      const executeResp = await fetch(executeUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceRoleKey}`,
        },
        body: JSON.stringify({ refundRequestId, approvedBy: 'admin' }),
      });

      if (!executeResp.ok) {
        const errBody = await executeResp.json().catch(() => ({}));
        const errMsg = (errBody as { error?: string }).error ?? 'execute-refund failed';
        console.error('[admin-refund] execute-refund error:', errMsg);
        return errorResponse(errMsg, 'execute_failed', 502);
      }

      // 更新退款申请状态
      await serviceClient
        .from('refund_requests')
        .update({
          status: 'approved_admin',
          admin_decision: 'approved',
          admin_reason: adminReason?.trim() ?? null,
          admin_decided_at: now,
          admin_decided_by: userId,
          updated_at: now,
        })
        .eq('id', refundRequestId);

      // 单笔争议 Store Credit 不更新整单状态（避免 V3 多单混状态）
      if (!refundReq.order_item_id) {
        await serviceClient
          .from('orders')
          .update({ status: 'refunded', refunded_at: now, updated_at: now })
          .eq('id', refundReq.order_id);
      }

      return jsonResponse({ success: true, status: 'approved_admin' });
    } else {
      // 最终拒绝
      await serviceClient
        .from('refund_requests')
        .update({
          status: 'rejected_admin',
          admin_decision: 'rejected',
          admin_reason: adminReason?.trim() ?? null,
          admin_decided_at: now,
          admin_decided_by: userId,
          updated_at: now,
        })
        .eq('id', refundRequestId);

      if (!refundReq.order_item_id) {
        await serviceClient
          .from('orders')
          .update({ status: 'refund_rejected', updated_at: now })
          .eq('id', refundReq.order_id);

        await serviceClient
          .from('coupons')
          .update({ status: 'used' })
          .eq('order_id', refundReq.order_id);
      } else {
        await serviceClient
          .from('coupons')
          .update({ status: 'used', updated_at: now })
          .eq('order_item_id', refundReq.order_item_id);
      }

      // 发送 C14 管理员最终拒绝退款通知邮件
      try {
        const { data: userInfo } = await serviceClient
          .from('users')
          .select('email')
          .eq('id', refundReq.user_id)
          .single();

        if (userInfo?.email) {
          const orderNumber = (refundReq.orders as { order_number: string } | null)?.order_number ?? '';
          const { subject, html } = buildC14Email({
            orderNumber,
            refundAmount: refundReq.refund_amount,
            adminReason:  adminReason?.trim() ?? '',
          });
          await sendEmail(serviceClient, {
            to:            userInfo.email,
            subject,
            htmlBody:      html,
            emailCode:     'C14',
            referenceId:   refundRequestId,
            recipientType: 'customer',
            userId:        refundReq.user_id,
          });
        }
      } catch (emailErr) {
        console.error('[admin-refund] C14 email error:', emailErr);
      }

      return jsonResponse({ success: true, status: 'rejected_admin' });
    }
  } catch (err) {
    console.error('[admin-refund] error:', err);
    return jsonResponse(
      { error: err instanceof Error ? err.message : 'Unknown error' },
      500,
    );
  }
});

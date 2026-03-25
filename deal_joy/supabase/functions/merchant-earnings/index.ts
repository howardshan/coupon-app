// =============================================================
// Edge Function: merchant-earnings
// 财务与结算模块
// 路由：
//   GET /merchant-earnings/summary             — 收入概览（月份汇总）
//   GET /merchant-earnings/transactions        — 交易明细（分页 + 日期筛选）
//   GET /merchant-earnings/settlement-schedule — 结算规则 + 下次打款时间
//   GET /merchant-earnings/report              — 对账报表（P2）
// 认证：Bearer JWT（merchant 用户，通过 auth.uid() 关联 merchants 表）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

// 统一 JSON 响应
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 错误响应
function errorResponse(message: string, code: string, status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

// 格式化日期为 YYYY-MM-DD 字符串
function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// 计算月份起始日（给定 YYYY-MM 返回 YYYY-MM-01）
function parseMonthStart(monthStr: string): string {
  // 格式: 2026-03 → 2026-03-01
  if (/^\d{4}-\d{2}$/.test(monthStr)) {
    return `${monthStr}-01`;
  }
  // 格式: 2026-03-01 直接使用
  return monthStr;
}

// =============================================================
// 主入口
// =============================================================
serve(async (req: Request) => {
  // OPTIONS 预检
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 仅支持 GET
  if (req.method !== 'GET') {
    return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }

  // 初始化 Supabase 环境变量
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  // 验证 Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse('Missing authorization header', 'unauthorized', 401);
  }
  const userJwt = authHeader.replace('Bearer ', '');

  // 用 user JWT 初始化客户端（鉴权用）
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });

  // 验证 JWT 合法性
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }

  // 统一鉴权
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  let auth;
  try {
    auth = await resolveAuth(serviceClient, user.id, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 'unauthorized', 403);
  }
  requirePermission(auth, 'finance');

  // 查询商家详细信息（含 Stripe 账户信息）
  const { data: merchant, error: merchantError } = await serviceClient
    .from('merchants')
    .select('id, status, stripe_account_id, stripe_account_email, stripe_account_status')
    .eq('id', auth.merchantId)
    .single();

  if (merchantError || !merchant) {
    return errorResponse('Merchant account not found', 'merchant_not_found', 404);
  }

  // 解析 URL 路径（去掉 /merchant-earnings 前缀）
  const url = new URL(req.url);
  const pathname = url.pathname;
  // 路径段处理：支持 /merchant-earnings/summary 或 /summary
  const pathParts = pathname.split('/').filter(Boolean);
  // 取最后一段作为 sub-route
  const subRoute = pathParts[pathParts.length - 1] ?? 'summary';

  const searchParams = url.searchParams;

  // =============================================================
  // 路由分发
  // =============================================================
  if (subRoute === 'summary') {
    return handleSummary(serviceClient, merchant.id, user.id, searchParams);
  }

  if (subRoute === 'transactions') {
    return handleTransactions(serviceClient, merchant.id, user.id, searchParams);
  }

  if (subRoute === 'settlement-schedule') {
    return handleSettlementSchedule(serviceClient, merchant.id, user.id);
  }

  if (subRoute === 'report') {
    return handleReport(serviceClient, merchant.id, user.id, searchParams);
  }

  if (subRoute === 'commission-config') {
    return handleCommissionConfig(serviceClient, auth.merchantId);
  }

  // 返回账户信息（默认路由 /merchant-earnings）
  if (subRoute === 'merchant-earnings' || subRoute === 'account') {
    return handleAccount(merchant);
  }

  return errorResponse('Route not found', 'not_found', 404);
});

// =============================================================
// 处理函数: 收入概览 GET /summary?month=2026-03
// =============================================================
async function handleSummary(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  userId: string,
  params: URLSearchParams,
): Promise<Response> {
  try {
    // 默认当月
    const now = new Date();
    const defaultMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const monthParam = params.get('month') ?? defaultMonth;
    const monthStart = parseMonthStart(monthParam);

    // 调用 DB 函数 get_merchant_earnings_summary
    const { data, error } = await client.rpc('get_merchant_earnings_summary', {
      p_merchant_id: merchantId,
      p_month_start: monthStart,
    });

    if (error) {
      console.error('earnings summary error:', error);
      return errorResponse('Failed to fetch earnings summary', 'db_error', 500);
    }

    // DB 函数返回单行结果
    const row = Array.isArray(data) ? data[0] : data;

    return jsonResponse({
      month: monthParam,
      month_start: monthStart,
      total_revenue: parseFloat(row?.total_revenue ?? '0'),
      pending_settlement: parseFloat(row?.pending_settlement ?? '0'),
      settled_amount: parseFloat(row?.settled_amount ?? '0'),
      refunded_amount: parseFloat(row?.refunded_amount ?? '0'),
    });
  } catch (e) {
    console.error('handleSummary error:', e);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// 处理函数: 交易明细 GET /transactions?date_from=&date_to=&page=1&per_page=20
// =============================================================
async function handleTransactions(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  userId: string,
  params: URLSearchParams,
): Promise<Response> {
  try {
    const dateFrom = params.get('date_from') || null;
    const dateTo   = params.get('date_to')   || null;
    const page     = Math.max(1, parseInt(params.get('page') ?? '1'));
    const perPage  = Math.min(100, Math.max(1, parseInt(params.get('per_page') ?? '20')));

    const { data, error } = await client.rpc('get_merchant_transactions', {
      p_merchant_id: merchantId,
      p_date_from:   dateFrom,
      p_date_to:     dateTo,
      p_page:        page,
      p_per_page:    perPage,
    });

    if (error) {
      console.error('transactions error:', error);
      return errorResponse('Failed to fetch transactions', 'db_error', 500);
    }

    const rows = Array.isArray(data) ? data : [];
    const totalCount = rows.length > 0 ? parseInt(rows[0].total_count ?? '0') : 0;

    // 聚合合计行（含 stripe_fee）
    const totals = rows.reduce(
      (acc: { amount: number; platform_fee: number; stripe_fee: number; net_amount: number }, row: {
        amount: string;
        platform_fee: string;
        stripe_fee: string;
        net_amount: string;
      }) => ({
        amount: acc.amount + parseFloat(row.amount ?? '0'),
        platform_fee: acc.platform_fee + parseFloat(row.platform_fee ?? '0'),
        stripe_fee: acc.stripe_fee + parseFloat(row.stripe_fee ?? '0'),
        net_amount: acc.net_amount + parseFloat(row.net_amount ?? '0'),
      }),
      { amount: 0, platform_fee: 0, stripe_fee: 0, net_amount: 0 },
    );

    return jsonResponse({
      data: rows.map((row: {
        order_id: string;
        deal_title: string;
        validity_type: string;
        amount: string;
        platform_fee_rate: string;
        platform_fee: string;
        stripe_fee: string;
        net_amount: string;
        status: string;
        created_at: string;
        total_count: string;
      }) => ({
        order_id:          row.order_id,
        deal_title:        row.deal_title ?? '',
        validity_type:     row.validity_type ?? 'fixed_date',
        amount:            parseFloat(row.amount ?? '0'),
        platform_fee_rate: parseFloat(row.platform_fee_rate ?? '0'),
        platform_fee:      parseFloat(row.platform_fee ?? '0'),
        stripe_fee:        parseFloat(row.stripe_fee ?? '0'),
        net_amount:        parseFloat(row.net_amount ?? '0'),
        status:            row.status,
        created_at:        row.created_at,
      })),
      pagination: {
        page,
        per_page: perPage,
        total: totalCount,
        has_more: page * perPage < totalCount,
      },
      totals: {
        amount:       Math.round(totals.amount * 100) / 100,
        platform_fee: Math.round(totals.platform_fee * 100) / 100,
        stripe_fee:   Math.round(totals.stripe_fee * 100) / 100,
        net_amount:   Math.round(totals.net_amount * 100) / 100,
      },
    });
  } catch (e) {
    console.error('handleTransactions error:', e);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// 处理函数: 结算规则 + 下次打款时间 GET /settlement-schedule
// =============================================================
async function handleSettlementSchedule(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  userId: string,
): Promise<Response> {
  try {
    // 查询最早一批 pending 核销订单（status=used 且 used_at < 7天前的不算 pending）
    const now = new Date();
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // 查询所有已核销但尚未进入 paid settlement 的订单
    const { data: pendingOrders, error: pendingError } = await client
      .from('coupons')
      .select('used_at, order_id, orders!inner(total_amount, deal_id, deals!inner(merchant_id))')
      .eq('orders.deals.merchant_id', merchantId)
      .eq('status', 'used')
      .gt('used_at', cutoff.toISOString())
      .order('used_at', { ascending: true })
      .limit(100);

    if (pendingError) {
      console.error('settlement schedule error:', pendingError);
      // 不阻断，返回默认规则
    }

    // 计算下次打款日期：最早核销时间 + 7 天
    let nextPayoutDate: string | null = null;
    let pendingAmount = 0;

    if (pendingOrders && pendingOrders.length > 0) {
      const earliest = pendingOrders[0];
      if (earliest.used_at) {
        const payoutDate = new Date(earliest.used_at);
        payoutDate.setDate(payoutDate.getDate() + 7);
        nextPayoutDate = formatDate(payoutDate);
      }

      // 合计待结算金额（商家实收 85%）
      pendingAmount = (pendingOrders as Array<{
        order_id: string;
        used_at: string | null;
        orders: { total_amount: number } | null;
      }>).reduce((sum, coupon) => {
        const amount = (coupon.orders as unknown as { total_amount: number } | null)?.total_amount ?? 0;
        return sum + amount * 0.85;
      }, 0);
    }

    return jsonResponse({
      settlement_rule: 'Redeemed orders are settled T+7 days after redemption via Stripe Connect',
      settlement_days: 7,
      next_payout_date: nextPayoutDate,
      pending_amount: Math.round(pendingAmount * 100) / 100,
      pending_order_count: pendingOrders?.length ?? 0,
    });
  } catch (e) {
    console.error('handleSettlementSchedule error:', e);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// 处理函数: 对账报表 GET /report?period_type=monthly&year=2026&month=3
// =============================================================
async function handleReport(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  userId: string,
  params: URLSearchParams,
): Promise<Response> {
  try {
    const periodType = params.get('period_type') ?? 'monthly'; // 'monthly' | 'weekly'
    const year       = parseInt(params.get('year') ?? String(new Date().getFullYear()));
    const month      = parseInt(params.get('month') ?? String(new Date().getMonth() + 1));
    const week       = parseInt(params.get('week') ?? '1');

    let dateFrom: string;
    let dateTo: string;

    if (periodType === 'weekly') {
      // 计算指定周的起止日期
      const d = new Date(year, 0, 1 + (week - 1) * 7);
      const dayOfWeek = d.getDay();
      const startOfWeek = new Date(d);
      startOfWeek.setDate(d.getDate() - dayOfWeek);
      const endOfWeek = new Date(startOfWeek);
      endOfWeek.setDate(startOfWeek.getDate() + 6);
      dateFrom = formatDate(startOfWeek);
      dateTo   = formatDate(endOfWeek);
    } else {
      // 月报：指定月的起止
      const startDate = new Date(year, month - 1, 1);
      const endDate   = new Date(year, month, 0); // 月末
      dateFrom = formatDate(startDate);
      dateTo   = formatDate(endDate);
    }

    const { data, error } = await client.rpc('get_merchant_report_data', {
      p_merchant_id: merchantId,
      p_date_from:   dateFrom,
      p_date_to:     dateTo,
    });

    if (error) {
      console.error('report error:', error);
      return errorResponse('Failed to fetch report data', 'db_error', 500);
    }

    const rows = Array.isArray(data) ? data : [];

    // 计算合计（含 stripe_fee）
    const totals = rows.reduce(
      (acc: { order_count: number; gross_amount: number; platform_fee: number; stripe_fee: number; net_amount: number }, row: {
        order_count: string;
        gross_amount: string;
        platform_fee: string;
        stripe_fee: string;
        net_amount: string;
      }) => ({
        order_count:  acc.order_count  + parseInt(row.order_count ?? '0'),
        gross_amount: acc.gross_amount + parseFloat(row.gross_amount ?? '0'),
        platform_fee: acc.platform_fee + parseFloat(row.platform_fee ?? '0'),
        stripe_fee:   acc.stripe_fee   + parseFloat(row.stripe_fee ?? '0'),
        net_amount:   acc.net_amount   + parseFloat(row.net_amount ?? '0'),
      }),
      { order_count: 0, gross_amount: 0, platform_fee: 0, stripe_fee: 0, net_amount: 0 },
    );

    return jsonResponse({
      period_type: periodType,
      date_from:   dateFrom,
      date_to:     dateTo,
      rows: rows.map((row: {
        report_date: string;
        order_count: string;
        gross_amount: string;
        platform_fee: string;
        stripe_fee: string;
        net_amount: string;
      }) => ({
        date:         row.report_date,
        order_count:  parseInt(row.order_count ?? '0'),
        gross_amount: parseFloat(row.gross_amount ?? '0'),
        platform_fee: parseFloat(row.platform_fee ?? '0'),
        stripe_fee:   parseFloat(row.stripe_fee ?? '0'),
        net_amount:   parseFloat(row.net_amount ?? '0'),
      })),
      totals: {
        order_count:  totals.order_count,
        gross_amount: Math.round(totals.gross_amount * 100) / 100,
        platform_fee: Math.round(totals.platform_fee * 100) / 100,
        stripe_fee:   Math.round(totals.stripe_fee * 100) / 100,
        net_amount:   Math.round(totals.net_amount * 100) / 100,
      },
    });
  } catch (e) {
    console.error('handleReport error:', e);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// 处理函数: 抽成配置 GET /commission-config
// 返回全局费率配置 + 该商家的免费期状态
// =============================================================
async function handleCommissionConfig(
  client: ReturnType<typeof createClient>,
  merchantId: string,
): Promise<Response> {
  try {
    // 同时查全局配置表和商家表（新增 commission_rate 统一费率字段）
    const [configRes, merchantRes] = await Promise.all([
      client
        .from('platform_commission_config')
        .select('free_months, commission_rate, stripe_processing_rate, stripe_flat_fee, effective_from, effective_to')
        .single(),
      client
        .from('merchants')
        .select('commission_free_until, commission_rate, commission_stripe_rate, commission_stripe_flat_fee, commission_effective_from, commission_effective_to')
        .eq('id', merchantId)
        .single(),
    ]);

    if (configRes.error) {
      console.error('commission config error:', configRes.error);
      return errorResponse('Failed to fetch commission config', 'db_error', 500);
    }

    const config = configRes.data;
    const m = merchantRes.data ?? {};
    const commissionFreeUntil = m.commission_free_until ?? null;
    // 免费期含当天：用 DATE 比较
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const freeUntilDate = commissionFreeUntil ? new Date(commissionFreeUntil) : null;
    if (freeUntilDate) freeUntilDate.setHours(0, 0, 0, 0);
    const isInFreePeriod = freeUntilDate ? today <= freeUntilDate : false;

    // 判断商家自定义费率是否在生效期内
    const mEffFrom = m.commission_effective_from ? new Date(m.commission_effective_from) : null;
    const mEffTo = m.commission_effective_to ? new Date(m.commission_effective_to) : null;
    const hasMerchantRates = m.commission_rate != null
      || m.commission_stripe_rate != null || m.commission_stripe_flat_fee != null;
    let merchantRatesActive = false;
    if (hasMerchantRates) {
      if (!mEffFrom && !mEffTo) {
        merchantRatesActive = true; // 没设生效期 → 永久生效
      } else if (mEffFrom && mEffTo) {
        merchantRatesActive = today >= mEffFrom && today <= mEffTo;
      } else if (mEffFrom) {
        merchantRatesActive = today >= mEffFrom;
      } else if (mEffTo) {
        merchantRatesActive = today <= mEffTo;
      }
    }

    // 全局统一费率
    const globalCommissionRate = parseFloat(config.commission_rate ?? '0.15');
    // 实际生效的统一费率（商家专属 > 全局默认）
    const effectiveCommissionRate = merchantRatesActive && m.commission_rate != null
      ? parseFloat(m.commission_rate)
      : globalCommissionRate;

    // Stripe 手续费（保留原有逻辑）
    const effectiveStripeRate = merchantRatesActive && m.commission_stripe_rate != null
      ? parseFloat(m.commission_stripe_rate) : parseFloat(config.stripe_processing_rate ?? '0.03');
    const effectiveStripeFlatFee = merchantRatesActive && m.commission_stripe_flat_fee != null
      ? parseFloat(m.commission_stripe_flat_fee) : parseFloat(config.stripe_flat_fee ?? '0.30');

    // 实际生效费率
    const effectiveRates = {
      commission_rate: effectiveCommissionRate,
      stripe_processing_rate: effectiveStripeRate,
      stripe_flat_fee: effectiveStripeFlatFee,
    };

    return jsonResponse({
      free_months:                config.free_months,
      commission_rate:            globalCommissionRate,
      stripe_processing_rate:     parseFloat(config.stripe_processing_rate ?? '0.03'),
      stripe_flat_fee:            parseFloat(config.stripe_flat_fee ?? '0.30'),
      commission_free_until:      commissionFreeUntil,
      is_in_free_period:          isInFreePeriod,
      merchant_rates_active:      merchantRatesActive,
      effective_commission_rate:  effectiveCommissionRate,
      effective_rates:            effectiveRates,
    });
  } catch (e) {
    console.error('handleCommissionConfig error:', e);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// 处理函数: Stripe 账户状态 GET /account
// =============================================================
function handleAccount(merchant: {
  id: string;
  stripe_account_id?: string;
  stripe_account_email?: string;
  stripe_account_status?: string;
}): Response {
  const isConnected = merchant.stripe_account_status === 'connected';
  return jsonResponse({
    is_connected: isConnected,
    account_id:     merchant.stripe_account_id ?? null,
    account_email:  merchant.stripe_account_email ?? null,
    account_status: merchant.stripe_account_status ?? 'not_connected',
  });
}

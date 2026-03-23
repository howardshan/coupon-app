// =============================================================
// Edge Function: merchant-withdrawal
// 提现系统：余额查询、手动提现、提现记录、银行账户、自动提现设置
// 路由:
//   GET  /merchant-withdrawal/balance      — 可提现余额
//   POST /merchant-withdrawal/withdraw     — 发起手动提现（仅 store_owner）
//   GET  /merchant-withdrawal/history      — 提现记录
//   POST /merchant-withdrawal/bank-account — 绑定 Stripe Connect 账户（仅 store_owner）
//   GET  /merchant-withdrawal/bank-account — 查看银行账户状态
//   PATCH /merchant-withdrawal/settings    — 设置自动提现（仅 store_owner）
//   GET  /merchant-withdrawal/settings     — 获取自动提现设置
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";
import { sendEmail, getAdminRecipients } from "../_shared/email.ts";
import { buildM14Email } from "../_shared/email-templates/merchant/withdrawal-request.ts";
import { buildA7Email } from "../_shared/email-templates/admin/withdrawal-pending.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("Missing authorization header", 401);
  }

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    }
  );

  const {
    data: { user },
    error: authError,
  } = await supabaseUser.auth.getUser();

  if (authError || !user) {
    return errorResponse("Unauthorized", 401);
  }

  // 统一鉴权
  let auth;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 403);
  }
  requirePermission(auth, "finance");

  const merchantId = auth.merchantId;

  // 解析路由
  const url = new URL(req.url);
  const pathParts = url.pathname
    .replace(/\/merchant-withdrawal\/?/, "")
    .split("/")
    .filter(Boolean);
  const subRoute = pathParts[0] ?? "";

  try {
    // -------------------------------------------------------
    // GET /balance — 可提现余额
    // -------------------------------------------------------
    if (req.method === "GET" && subRoute === "balance") {
      return await handleGetBalance(supabaseAdmin, merchantId);
    }

    // -------------------------------------------------------
    // POST /withdraw — 发起手动提现（仅 store_owner）
    // -------------------------------------------------------
    if (req.method === "POST" && subRoute === "withdraw") {
      // 仅 store_owner 可以提现
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can initiate withdrawal", 403);
      }
      const body = await req.json();
      return await handleWithdraw(supabaseAdmin, merchantId, user.id, body);
    }

    // -------------------------------------------------------
    // GET /history — 提现记录
    // -------------------------------------------------------
    if (req.method === "GET" && subRoute === "history") {
      return await handleGetHistory(supabaseAdmin, merchantId, url);
    }

    // -------------------------------------------------------
    // POST /bank-account — 绑定银行账户
    // -------------------------------------------------------
    if (req.method === "POST" && subRoute === "bank-account") {
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can manage bank accounts", 403);
      }
      const body = await req.json();
      return await handleAddBankAccount(supabaseAdmin, merchantId, body);
    }

    // -------------------------------------------------------
    // GET /bank-account — 查看银行账户
    // -------------------------------------------------------
    if (req.method === "GET" && subRoute === "bank-account") {
      return await handleGetBankAccount(supabaseAdmin, merchantId);
    }

    // -------------------------------------------------------
    // PATCH /settings — 设置自动提现
    // -------------------------------------------------------
    if (req.method === "PATCH" && subRoute === "settings") {
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can manage withdrawal settings", 403);
      }
      const body = await req.json();
      return await handleUpdateSettings(supabaseAdmin, merchantId, body);
    }

    // -------------------------------------------------------
    // GET /settings — 获取自动提现设置
    // -------------------------------------------------------
    if (req.method === "GET" && subRoute === "settings") {
      return await handleGetSettings(supabaseAdmin, merchantId);
    }

    return errorResponse("Not found", 404);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Internal server error";
    return errorResponse(msg, 500);
  }
});

// =============================================================
// GET /balance — 可提现余额
// 计算规则：已核销 T+7 天的净收入 - 已提现 - 退款扣除
// =============================================================
async function handleGetBalance(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  const now = new Date();
  const settledCutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  // 查询已核销且满 T+7 的券对应订单金额（按实际核销门店归属）
  const { data: settledCoupons, error: settledError } = await admin
    .from("coupons")
    .select("order_id, orders!inner(total_amount, platform_fee, net_amount)")
    .or(`redeemed_at_merchant_id.eq.${merchantId},and(redeemed_at_merchant_id.is.null,merchant_id.eq.${merchantId})`)
    .eq("status", "used")
    .lt("used_at", settledCutoff.toISOString());

  if (settledError) {
    return errorResponse(`Failed to query settled coupons: ${settledError.message}`, 500);
  }

  // 计算已结算总额（商家实收 = net_amount = total_amount - platform_fee）
  let totalSettled = 0;
  for (const coupon of settledCoupons ?? []) {
    // deno-lint-ignore no-explicit-any
    const order = (coupon as any).orders;
    if (order) {
      totalSettled += parseFloat(order.net_amount ?? order.total_amount * 0.85 ?? 0);
    }
  }

  // 查询已提现总额（completed + processing）
  const { data: withdrawals } = await admin
    .from("withdrawals")
    .select("amount, status")
    .eq("merchant_id", merchantId)
    .in("status", ["completed", "processing", "pending"]);

  let totalWithdrawn = 0;
  for (const w of withdrawals ?? []) {
    totalWithdrawn += parseFloat(String(w.amount));
  }

  // 查询退款扣除（已结算后发生的退款）
  const { data: refundedCoupons } = await admin
    .from("coupons")
    .select("order_id, orders!inner(net_amount)")
    .or(`redeemed_at_merchant_id.eq.${merchantId},and(redeemed_at_merchant_id.is.null,merchant_id.eq.${merchantId})`)
    .eq("status", "refunded");

  let totalRefundDeductions = 0;
  for (const coupon of refundedCoupons ?? []) {
    // deno-lint-ignore no-explicit-any
    const order = (coupon as any).orders;
    if (order) {
      totalRefundDeductions += parseFloat(order.net_amount ?? 0);
    }
  }

  const availableBalance = Math.max(0, totalSettled - totalWithdrawn - totalRefundDeductions);

  return jsonResponse({
    available_balance: Math.round(availableBalance * 100) / 100,
    total_settled: Math.round(totalSettled * 100) / 100,
    total_withdrawn: Math.round(totalWithdrawn * 100) / 100,
    total_refund_deductions: Math.round(totalRefundDeductions * 100) / 100,
    currency: "usd",
  });
}

// =============================================================
// POST /withdraw — 发起手动提现
// =============================================================
async function handleWithdraw(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  userId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const amount = Number(body.amount);
  if (!amount || amount <= 0) {
    return errorResponse("Invalid withdrawal amount");
  }

  // 最低提现金额 $10
  if (amount < 10) {
    return errorResponse("Minimum withdrawal amount is $10.00");
  }

  // 检查是否有绑定的银行账户
  const { data: bankAccount } = await admin
    .from("merchant_bank_accounts")
    .select("id, stripe_account_id, status")
    .eq("merchant_id", merchantId)
    .eq("is_default", true)
    .eq("status", "verified")
    .maybeSingle();

  if (!bankAccount) {
    return errorResponse("No verified bank account found. Please connect your Stripe account first.");
  }

  // 检查是否有未完成的提现
  const { data: pendingWithdrawal } = await admin
    .from("withdrawals")
    .select("id")
    .eq("merchant_id", merchantId)
    .in("status", ["pending", "processing"])
    .maybeSingle();

  if (pendingWithdrawal) {
    return errorResponse("You already have a pending withdrawal. Please wait for it to complete.");
  }

  // 创建提现记录
  const { data: withdrawal, error } = await admin
    .from("withdrawals")
    .insert({
      merchant_id: merchantId,
      amount,
      status: "pending",
      bank_account_id: bankAccount.id,
      requested_by: userId,
      requested_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (error) {
    return errorResponse(`Failed to create withdrawal: ${error.message}`, 500);
  }

  // TODO: 调用 Stripe Transfer/Payout API 执行实际转账（V2）
  // 这里先创建记录，后续通过 webhook 或 cron 处理实际转账

  // M14 + A7：通知商家申请已受理，同时告知管理员（fire-and-forget）
  (async () => {
    try {
      // 查询商家名称和用户邮箱
      const { data: merchantInfo } = await admin
        .from("merchants").select("name, user_id").eq("id", merchantId).single();
      if (merchantInfo) {
        const { data: userInfo } = await admin
          .from("users").select("email").eq("id", merchantInfo.user_id).single();

        // M14：通知商家
        if (userInfo?.email) {
          const { subject: m14Subject, html: m14Html } = buildM14Email({
            merchantName: merchantInfo.name,
            withdrawalId: withdrawal.id,
            amount,
            requestedAt: withdrawal.requested_at,
          });
          await sendEmail(admin, {
            to: userInfo.email, subject: m14Subject, htmlBody: m14Html,
            emailCode: "M14", referenceId: withdrawal.id, recipientType: "merchant",
            merchantId,
          });
        }

        // A7：通知管理员
        const adminEmails = await getAdminRecipients(admin, "A7");
        if (adminEmails.length > 0) {
          const { subject: a7Subject, html: a7Html } = buildA7Email({
            merchantName: merchantInfo.name,
            merchantId,
            withdrawalId: withdrawal.id,
            amount,
            requestedAt: withdrawal.requested_at,
          });
          await sendEmail(admin, {
            to: adminEmails, subject: a7Subject, htmlBody: a7Html,
            emailCode: "A7", referenceId: withdrawal.id, recipientType: "admin",
          });
        }
      }
    } catch (err) {
      console.warn("[merchant-withdrawal] email notification failed", err);
    }
  })();

  return jsonResponse({ withdrawal }, 201);
}

// =============================================================
// GET /history — 提现记录（分页）
// =============================================================
async function handleGetHistory(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  url: URL
): Promise<Response> {
  const page = Math.max(1, parseInt(url.searchParams.get("page") ?? "1"));
  const perPage = Math.min(50, Math.max(1, parseInt(url.searchParams.get("per_page") ?? "20")));
  const offset = (page - 1) * perPage;

  const { data, error, count } = await admin
    .from("withdrawals")
    .select("*", { count: "exact" })
    .eq("merchant_id", merchantId)
    .order("requested_at", { ascending: false })
    .range(offset, offset + perPage - 1);

  if (error) {
    return errorResponse(`Failed to fetch withdrawal history: ${error.message}`, 500);
  }

  return jsonResponse({
    data: data ?? [],
    pagination: {
      page,
      per_page: perPage,
      total: count ?? 0,
      has_more: offset + perPage < (count ?? 0),
    },
  });
}

// =============================================================
// POST /bank-account — 绑定 Stripe Connect 银行账户
// =============================================================
async function handleAddBankAccount(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const stripeAccountId = body.stripe_account_id as string;
  if (!stripeAccountId) {
    return errorResponse("stripe_account_id is required");
  }

  // 取消之前的默认账户
  await admin
    .from("merchant_bank_accounts")
    .update({ is_default: false })
    .eq("merchant_id", merchantId);

  // 插入新账户记录
  const { data: account, error } = await admin
    .from("merchant_bank_accounts")
    .upsert({
      merchant_id: merchantId,
      stripe_account_id: stripeAccountId,
      status: body.status as string ?? "pending",
      bank_name: body.bank_name as string ?? null,
      last4: body.last4 as string ?? null,
      is_default: true,
    }, { onConflict: "merchant_id,stripe_account_id" })
    .select()
    .single();

  if (error) {
    return errorResponse(`Failed to save bank account: ${error.message}`, 500);
  }

  // 同步到 merchants 表的 stripe 字段
  await admin
    .from("merchants")
    .update({
      stripe_account_id: stripeAccountId,
      stripe_account_status: body.status as string ?? "pending",
    })
    .eq("id", merchantId);

  return jsonResponse({ bank_account: account }, 201);
}

// =============================================================
// GET /bank-account — 查看银行账户
// =============================================================
async function handleGetBankAccount(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  const { data: accounts, error } = await admin
    .from("merchant_bank_accounts")
    .select("*")
    .eq("merchant_id", merchantId)
    .order("is_default", { ascending: false });

  if (error) {
    return errorResponse(`Failed to fetch bank accounts: ${error.message}`, 500);
  }

  return jsonResponse({ bank_accounts: accounts ?? [] });
}

// =============================================================
// PATCH /settings — 更新自动提现设置
// =============================================================
async function handleUpdateSettings(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const settingsData: Record<string, unknown> = {
    merchant_id: merchantId,
    updated_at: new Date().toISOString(),
  };

  if (body.auto_withdrawal_enabled !== undefined) {
    settingsData.auto_withdrawal_enabled = Boolean(body.auto_withdrawal_enabled);
  }
  if (body.auto_withdrawal_frequency !== undefined) {
    const validFreqs = ["daily", "weekly", "biweekly", "monthly"];
    if (!validFreqs.includes(body.auto_withdrawal_frequency as string)) {
      return errorResponse(`Invalid frequency. Must be one of: ${validFreqs.join(", ")}`);
    }
    settingsData.auto_withdrawal_frequency = body.auto_withdrawal_frequency;
  }
  if (body.auto_withdrawal_day !== undefined) {
    settingsData.auto_withdrawal_day = Number(body.auto_withdrawal_day);
  }
  if (body.min_withdrawal_amount !== undefined) {
    const minAmount = Number(body.min_withdrawal_amount);
    if (minAmount < 10) {
      return errorResponse("Minimum withdrawal amount cannot be less than $10.00");
    }
    settingsData.min_withdrawal_amount = minAmount;
  }

  const { data, error } = await admin
    .from("merchant_withdrawal_settings")
    .upsert(settingsData, { onConflict: "merchant_id" })
    .select()
    .single();

  if (error) {
    return errorResponse(`Failed to update settings: ${error.message}`, 500);
  }

  return jsonResponse({ settings: data });
}

// =============================================================
// GET /settings — 获取自动提现设置
// =============================================================
async function handleGetSettings(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  const { data, error } = await admin
    .from("merchant_withdrawal_settings")
    .select("*")
    .eq("merchant_id", merchantId)
    .maybeSingle();

  if (error) {
    return errorResponse(`Failed to fetch settings: ${error.message}`, 500);
  }

  // 如果没有设置记录，返回默认值
  const settings = data ?? {
    auto_withdrawal_enabled: false,
    auto_withdrawal_frequency: "weekly",
    auto_withdrawal_day: 1,
    min_withdrawal_amount: 50.00,
  };

  return jsonResponse({ settings });
}

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

// 使用 npm: 而非 esm.sh：后者在 Edge Runtime 下会拉入 std/node，触发
// Deno.core.runMicrotasks() is not supported（见 Supabase 文档中 Stripe + esm.sh 排错说明）
import Stripe from "npm:stripe@14.25.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";
import { sendEmail, getAdminRecipients } from "../_shared/email.ts";
import { buildM14Email } from "../_shared/email-templates/merchant/withdrawal-request.ts";
import { buildM15Email } from "../_shared/email-templates/merchant/withdrawal-completed.ts";
import { buildM18Email } from "../_shared/email-templates/merchant/withdrawal-failed.ts";
import { buildA7Email } from "../_shared/email-templates/admin/withdrawal-pending.ts";

// Stripe 客户端（与 stripe-webhook 保持相同初始化方式）
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

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

/**
 * Stripe Account Links 要求 return_url / refresh_url 为 Stripe 可接受的 URL。
 * 自定义 scheme（如 dealjoymerchant://）会触发 Stripe 报错 "Not a valid URL"。
 * 必须在 Supabase Secrets 中配置两个 **https** 地址（可由静态页再 302/JS 跳回 App 深链）。
 */
function resolveStripeConnectRedirectUrls():
  | { returnUrl: string; refreshUrl: string }
  | { error: string } {
  const returnUrl = (Deno.env.get("STRIPE_CONNECT_RETURN_URL") ?? "").trim();
  const refreshUrl = (Deno.env.get("STRIPE_CONNECT_REFRESH_URL") ?? "").trim();
  if (!returnUrl || !refreshUrl) {
    return {
      error:
        "Missing STRIPE_CONNECT_RETURN_URL or STRIPE_CONNECT_REFRESH_URL. " +
        "Set both to full https URLs in Supabase Edge Function secrets (see docs/plans/2026-03-24-merchant-withdrawal-testing.md).",
    };
  }
  try {
    const r = new URL(returnUrl);
    const f = new URL(refreshUrl);
    if (r.protocol !== "https:" || f.protocol !== "https:") {
      return {
        error:
          "STRIPE_CONNECT_RETURN_URL and STRIPE_CONNECT_REFRESH_URL must use https:// (Stripe rejects custom URL schemes).",
      };
    }
  } catch {
    return { error: "STRIPE_CONNECT_RETURN_URL or STRIPE_CONNECT_REFRESH_URL is not a valid URL." };
  }
  return { returnUrl, refreshUrl };
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
    // POST /connect — 创建 Stripe Connect Express 账户 + 生成 onboarding URL
    // -------------------------------------------------------
    if (req.method === "POST" && subRoute === "connect" && pathParts[1] === undefined) {
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can connect Stripe account", 403);
      }
      return await handleCreateConnectLink(supabaseAdmin, merchantId);
    }

    // -------------------------------------------------------
    // POST /connect/refresh — onboarding 完成后同步账户状态
    // -------------------------------------------------------
    if (req.method === "POST" && subRoute === "connect" && pathParts[1] === "refresh") {
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can refresh Stripe account", 403);
      }
      return await handleRefreshConnectStatus(supabaseAdmin, merchantId);
    }

    // -------------------------------------------------------
    // GET /connect/dashboard — 生成 Stripe Express Dashboard 链接
    // -------------------------------------------------------
    if (req.method === "GET" && subRoute === "connect" && pathParts[1] === "dashboard") {
      return await handleConnectDashboardLink(supabaseAdmin, merchantId);
    }

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

  // 创建提现记录（初始状态 pending，Transfer 成功后改为 processing）
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

  // 调用 Stripe Transfer API（从平台账户转账到商家 Connected Account）
  // stripe.transfers.create() 是同步操作：成功即代表转账完成，失败会抛出异常
  // 使用 withdrawal.id 作为幂等 Key，防止网络重试导致重复打款
  const completedAt = new Date().toISOString();
  try {
    const transfer = await stripe.transfers.create(
      {
        amount:      Math.round(amount * 100), // 转为分（cents）
        currency:    "usd",
        destination: bankAccount.stripe_account_id,
        metadata:    { withdrawal_id: withdrawal.id, merchant_id: merchantId },
      },
      { idempotencyKey: withdrawal.id }
    );

    // Transfer 成功：立即标记为 completed（同步操作，无需等待 Webhook）
    await admin
      .from("withdrawals")
      .update({
        stripe_transfer_id: transfer.id,
        status: "completed",
        completed_at: completedAt,
      })
      .eq("id", withdrawal.id);

    // FIFO 批量更新 order_items.merchant_status → 'paid'
    // 将本次提现对应的已结算核销记录标记为已打款
    (async () => {
      try {
        const settledCutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const { data: eligibleItems } = await admin
          .from("order_items")
          .select("id, unit_price, service_fee, redeemed_at")
          .eq("merchant_status", "unpaid")
          .lt("redeemed_at", settledCutoff)
          .or(`redeemed_merchant_id.eq.${merchantId},and(redeemed_merchant_id.is.null,purchased_merchant_id.eq.${merchantId})`)
          .order("redeemed_at", { ascending: true });

        if (eligibleItems && eligibleItems.length > 0) {
          const itemsToMark: string[] = [];
          let accumulated = 0;
          for (const item of eligibleItems) {
            if (accumulated >= amount - 0.01) break;
            const net = (item.unit_price ?? 0) - (item.service_fee ?? 0);
            accumulated += net;
            itemsToMark.push(item.id);
          }
          if (itemsToMark.length > 0) {
            await admin
              .from("order_items")
              .update({ merchant_status: "paid" })
              .in("id", itemsToMark);
          }
        }
      } catch (err) {
        console.warn("[merchant-withdrawal] order_items FIFO update failed", err);
      }
    })();

    // 发送邮件通知（fire-and-forget）
    (async () => {
      try {
        const { data: merchantInfo } = await admin
          .from("merchants").select("name, user_id").eq("id", merchantId).single();
        if (merchantInfo) {
          const { data: userInfo } = await admin
            .from("users").select("email").eq("id", merchantInfo.user_id).single();

          // M15：通知商家提现已完成
          if (userInfo?.email) {
            const { subject: m15Subject, html: m15Html } = buildM15Email({
              merchantName: merchantInfo.name,
              withdrawalId: withdrawal.id,
              amount,
              completedAt,
            });
            await sendEmail(admin, {
              to: userInfo.email, subject: m15Subject, htmlBody: m15Html,
              emailCode: "M15", referenceId: withdrawal.id, recipientType: "merchant",
              merchantId,
            });
          }
        }
      } catch (err) {
        console.warn("[merchant-withdrawal] M15 email failed", err);
      }
    })();

    withdrawal.status = "completed";
    withdrawal.stripe_transfer_id = transfer.id;
  } catch (stripeError) {
    // Stripe 调用失败：将记录标记为 failed，发送 M18 失败通知
    const reason = stripeError instanceof Error ? stripeError.message : "Stripe transfer failed";
    await admin
      .from("withdrawals")
      .update({ status: "failed", failure_reason: reason })
      .eq("id", withdrawal.id);

    // M18：通知商家提现失败（fire-and-forget）
    (async () => {
      try {
        const { data: merchantInfo } = await admin
          .from("merchants").select("name, user_id").eq("id", merchantId).single();
        if (merchantInfo) {
          const { data: userInfo } = await admin
            .from("users").select("email").eq("id", merchantInfo.user_id).single();
          if (userInfo?.email) {
            const { subject: m18Subject, html: m18Html } = buildM18Email({
              merchantName: merchantInfo.name,
              withdrawalId: withdrawal.id,
              amount,
              failedAt: new Date().toISOString(),
              failureReason: reason,
            });
            await sendEmail(admin, {
              to: userInfo.email, subject: m18Subject, htmlBody: m18Html,
              emailCode: "M18", referenceId: withdrawal.id, recipientType: "merchant",
              merchantId,
            });
          }
        }
      } catch (err) {
        console.warn("[merchant-withdrawal] M18 email failed", err);
      }
    })();

    return errorResponse(`Withdrawal failed: ${reason}`, 502);
  }

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
// POST /connect — 创建 Stripe Connect Express 账户 + 生成 onboarding URL
// 若商家已有 stripe_account_id，则直接续接（生成新 Account Link）
// =============================================================
async function handleCreateConnectLink(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  // 查询商家现有的 stripe_account_id
  const { data: merchant, error: merchantError } = await admin
    .from("merchants")
    .select("id, name, stripe_account_id, stripe_account_status")
    .eq("id", merchantId)
    .single();

  if (merchantError || !merchant) {
    return errorResponse("Merchant not found", 404);
  }

  let stripeAccountId = merchant.stripe_account_id as string | null;

  // 若没有，则先在 Stripe 创建 Express 账户
  if (!stripeAccountId) {
    const account = await stripe.accounts.create({
      type: "express",
      metadata: { merchant_id: merchantId, merchant_name: merchant.name },
    });
    stripeAccountId = account.id;

    // 写入 merchants 表
    await admin
      .from("merchants")
      .update({
        stripe_account_id: stripeAccountId,
        stripe_account_status: "pending",
      })
      .eq("id", merchantId);
  }

  const redirect = resolveStripeConnectRedirectUrls();
  if ("error" in redirect) {
    return errorResponse(redirect.error, 503);
  }

  // 生成 Account Link（onboarding URL）
  // return_url / refresh_url 由环境变量提供（须为 https，见 resolveStripeConnectRedirectUrls）
  const accountLink = await stripe.accountLinks.create({
    account: stripeAccountId,
    refresh_url: redirect.refreshUrl,
    return_url: redirect.returnUrl,
    type: "account_onboarding",
  });

  return jsonResponse({ url: accountLink.url });
}

// =============================================================
// POST /connect/refresh — onboarding 完成后同步账户状态到数据库
// =============================================================
async function handleRefreshConnectStatus(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  // 查询商家 stripe_account_id
  const { data: merchant } = await admin
    .from("merchants")
    .select("stripe_account_id")
    .eq("id", merchantId)
    .single();

  const stripeAccountId = merchant?.stripe_account_id as string | null;
  if (!stripeAccountId) {
    return errorResponse("No Stripe account linked. Please connect first.", 400);
  }

  // 从 Stripe 获取最新账户信息
  const account = await stripe.accounts.retrieve(stripeAccountId);

  // 判断账户状态
  const isConnected = account.charges_enabled && account.payouts_enabled;
  const accountStatus = isConnected ? "connected" : "restricted";

  // 提取银行账户信息（external_accounts 中第一个 bank_account）
  let bankName: string | null = null;
  let last4: string | null = null;
  const externalAccounts = account.external_accounts?.data ?? [];
  const bankAccount = externalAccounts.find((ea) => ea.object === "bank_account");
  if (bankAccount && bankAccount.object === "bank_account") {
    bankName = (bankAccount as Stripe.BankAccount).bank_name ?? null;
    last4    = (bankAccount as Stripe.BankAccount).last4 ?? null;
  }

  // 更新 merchants 表
  await admin
    .from("merchants")
    .update({
      stripe_account_status: accountStatus,
      stripe_account_email:  account.email ?? null,
    })
    .eq("id", merchantId);

  // upsert merchant_bank_accounts 记录
  const bankStatus = isConnected ? "verified" : "pending";
  await admin
    .from("merchant_bank_accounts")
    .upsert(
      {
        merchant_id:       merchantId,
        stripe_account_id: stripeAccountId,
        status:            bankStatus,
        bank_name:         bankName,
        last4:             last4,
        is_default:        true,
      },
      { onConflict: "merchant_id,stripe_account_id" }
    );

  return jsonResponse({
    account_status:  accountStatus,
    account_email:   account.email ?? null,
    account_id:      stripeAccountId,
    is_connected:    isConnected,
    bank_name:       bankName,
    last4:           last4,
  });
}

// =============================================================
// GET /connect/dashboard — 生成 Stripe Express Dashboard 管理链接
// （用于已连接商家点击 "Manage on Stripe"）
// =============================================================
async function handleConnectDashboardLink(
  admin: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  const { data: merchant } = await admin
    .from("merchants")
    .select("stripe_account_id, stripe_account_status")
    .eq("id", merchantId)
    .single();

  const stripeAccountId = merchant?.stripe_account_id as string | null;
  if (!stripeAccountId) {
    return errorResponse("No Stripe account linked.", 400);
  }

  if (merchant?.stripe_account_status !== "connected") {
    return errorResponse("Stripe account is not fully connected.", 400);
  }

  const loginLink = await stripe.accounts.createLoginLink(stripeAccountId);

  return jsonResponse({ url: loginLink.url });
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

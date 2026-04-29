import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

// ============================================================
// manage-payment-methods — 用户已保存卡片管理
//
// 路由：
//   GET    /manage-payment-methods/list        获取已保存卡片列表
//   POST   /manage-payment-methods/default     设置默认卡
//   DELETE /manage-payment-methods/:id         删除已保存的卡
//
// 鉴权：Bearer JWT → auth.getUser() → 查 users.stripe_customer_id
// ============================================================

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// 使用 service_role client，绕过 RLS 读写 users 表
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
};

// 统一错误响应
function errorResponse(message: string, status = 400) {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// 统一成功响应
function successResponse(data: unknown) {
  return new Response(
    JSON.stringify(data),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// ============================================================
// 从 Authorization header 解析当前用户，并返回 stripe_customer_id
// ============================================================
async function getStripeCustomerId(req: Request): Promise<{ customerId: string; error?: never } | { customerId?: never; error: Response }> {
  // 提取 JWT token
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { error: errorResponse('Missing or invalid Authorization header', 401) };
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  // 服务端校验 JWT（支持 ES256），避免 service_role + getUser(jwt) 本地算法限制
  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) {
    return { error: errorResponse('Unauthorized', 401) };
  }

  // 查询该用户的 stripe_customer_id
  const { data: userData, error: dbError } = await supabase
    .from('users')
    .select('stripe_customer_id')
    .eq('id', user.id)
    .single();

  if (dbError) {
    console.error('查询用户 stripe_customer_id 失败:', dbError);
    return { error: errorResponse('Failed to fetch user data', 500) };
  }

  const customerId = userData?.stripe_customer_id;
  if (!customerId) {
    // 用户尚未进行过支付，没有 Stripe Customer，返回空列表而非报错
    return { error: errorResponse('No payment methods saved yet', 404) };
  }

  return { customerId };
}

// ============================================================
// 主处理逻辑
// ============================================================
Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 路由匹配：
    //   GET  → 获取卡片列表
    //   POST body.action='create_setup_intent' → 创建 SetupIntent
    //   POST body.action='set_default' → 设置默认卡
    //   DELETE → 删除卡（paymentMethodId 从 body 取）
    // 注：Dart 端 functions.invoke 不传 URL 路径后缀，用 body.action 区分 POST 路由

    // -------------------------------------------------------
    // GET — 获取已保存卡片列表
    // -------------------------------------------------------
    if (req.method === 'GET') {
      const result = await getStripeCustomerId(req);
      if (result.error) {
        // 未找到 customer 时返回空列表，不报错
        if ((result.error as Response).status === 404) {
          return successResponse({ paymentMethods: [] });
        }
        return result.error;
      }
      const { customerId } = result;

      // 获取该 Customer 下所有已保存的 card 类型支付方式
      const pmList = await stripe.customers.listPaymentMethods(customerId, {
        type: 'card',
      });

      // 获取默认支付方式 ID
      const customerData = await stripe.customers.retrieve(customerId) as Stripe.Customer;
      let defaultPmId = customerData.invoice_settings?.default_payment_method as string | null;

      // B：若 Customer 未设置默认卡但已有卡，自动将第一张卡设为默认（与客户端 A 互补）
      if (!defaultPmId && pmList.data.length > 0) {
        const firstId = pmList.data[0].id;
        try {
          await stripe.customers.update(customerId, {
            invoice_settings: { default_payment_method: firstId },
          });
          defaultPmId = firstId;
        } catch (e) {
          console.error('自动设置默认支付方式失败:', e);
        }
      }

      // 格式化返回数据，只暴露必要字段（含账单地址）
      const paymentMethods = pmList.data.map((pm) => ({
        id: pm.id,
        brand: pm.card?.brand ?? 'unknown',          // visa / mastercard / amex 等
        last4: pm.card?.last4 ?? '****',
        expMonth: pm.card?.exp_month ?? 0,
        expYear: pm.card?.exp_year ?? 0,
        isDefault: pm.id === defaultPmId,
        // 从 Stripe PM 的 billing_details.address 提取账单地址（可能为 null）
        billingAddress: pm.billing_details?.address ? {
          line1: pm.billing_details.address.line1 || '',
          line2: pm.billing_details.address.line2 || '',
          city: pm.billing_details.address.city || '',
          state: pm.billing_details.address.state || '',
          postalCode: pm.billing_details.address.postal_code || '',
          country: pm.billing_details.address.country || 'US',
        } : null,
      }));

      return successResponse({ paymentMethods });
    }

    // -------------------------------------------------------
    // POST create_setup_intent — 创建 SetupIntent（用于前端保存新卡）
    // body: { action: 'create_setup_intent' }
    // 返回: { clientSecret, customerId, ephemeralKey }
    // -------------------------------------------------------
    if (req.method === 'POST') {
      const body = await req.json();

      if (body.action === 'create_setup_intent') {

      // 提取并校验 JWT token
      const authHeader = req.headers.get('Authorization');
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return errorResponse('Missing or invalid Authorization header', 401);
      }
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
      const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
      const authClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      });
      const { data: { user }, error: authError } = await authClient.auth.getUser();
      if (authError || !user) {
        return errorResponse('Unauthorized', 401);
      }

      // 查询用户记录，获取 stripe_customer_id、email、full_name
      const { data: userData, error: dbError } = await supabase
        .from('users')
        .select('stripe_customer_id, email, full_name')
        .eq('id', user.id)
        .single();

      if (dbError) {
        console.error('查询用户信息失败:', dbError);
        return errorResponse('Failed to fetch user data', 500);
      }

      let customerId = userData?.stripe_customer_id as string | null;

      // 若用户尚无 Stripe Customer，自动创建一个
      if (!customerId) {
        console.log('用户无 stripe_customer_id，自动创建 Stripe Customer:', user.id);

        const customer = await stripe.customers.create({
          email: userData?.email ?? user.email ?? '',
          name: userData?.full_name ?? '',
          metadata: { user_id: user.id },
        });
        customerId = customer.id;

        // 将新 customer_id 写回 users 表
        const { error: updateError } = await supabase
          .from('users')
          .update({ stripe_customer_id: customerId })
          .eq('id', user.id);

        if (updateError) {
          console.error('写回 stripe_customer_id 失败:', updateError);
          // 不阻断流程，继续使用刚创建的 customerId
        }
      }

      // 创建 SetupIntent，允许 off_session 场景（如自动续费）
      const setupIntent = await stripe.setupIntents.create({
        customer: customerId,
        usage: 'off_session',
      });

      // 创建 Ephemeral Key，供 Stripe SDK 在前端安全操作 Customer 对象
      const ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2024-04-10' },
      );

      return successResponse({
        clientSecret: setupIntent.client_secret,
        customerId,
        ephemeralKey: ephemeralKey.secret,
      });
    }

      // -------------------------------------------------------
      // POST update_card — 更新卡片过期日期 + 账单地址
      // body: { action: 'update_card', paymentMethodId, expMonth?, expYear?, billingAddress? }
      // -------------------------------------------------------
      if (body.action === 'update_card') {
        const result = await getStripeCustomerId(req);
        if (result.error) return result.error;
        const { customerId } = result;

        const { paymentMethodId, expMonth, expYear, billingAddress } = body;
        if (!paymentMethodId) {
          return errorResponse('paymentMethodId is required');
        }

        // 校验该支付方式确实属于此 Customer（防越权）
        const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
        if (pm.customer !== customerId) {
          return errorResponse('Payment method does not belong to this customer', 403);
        }

        // 构建更新参数
        const updateParams: Record<string, unknown> = {};

        // 更新过期日期
        if (expMonth !== undefined && expYear !== undefined) {
          updateParams.card = {
            exp_month: Number(expMonth),
            exp_year: Number(expYear),
          };
        }

        // 更新账单地址
        if (billingAddress) {
          updateParams.billing_details = {
            address: {
              line1: billingAddress.line1 || '',
              line2: billingAddress.line2 || '',
              city: billingAddress.city || '',
              state: billingAddress.state || '',
              postal_code: billingAddress.postalCode || '',
              country: billingAddress.country || 'US',
            },
          };
        }

        await stripe.paymentMethods.update(paymentMethodId, updateParams as any);

        return successResponse({ success: true });
      }

      // -------------------------------------------------------
      // POST set_default — 设置默认卡
      // body: { action: 'set_default', paymentMethodId: string }
      // -------------------------------------------------------
      if (body.action === 'set_default') {
        const result = await getStripeCustomerId(req);
        if (result.error) return result.error;
        const { customerId } = result;

        const { paymentMethodId } = body;
        if (!paymentMethodId) {
          return errorResponse('paymentMethodId is required');
        }

        // 校验该支付方式确实属于此 Customer（防越权）
        const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
        if (pm.customer !== customerId) {
          return errorResponse('Payment method does not belong to this customer', 403);
        }

        // 设置默认支付方式
        await stripe.customers.update(customerId, {
          invoice_settings: { default_payment_method: paymentMethodId },
        });

        return successResponse({ success: true });
      }

      return errorResponse('Unknown POST action');
    }

    // -------------------------------------------------------
    // DELETE — 删除已保存的卡
    // body: { paymentMethodId: string }
    // -------------------------------------------------------
    if (req.method === 'DELETE') {
      const body = await req.json();
      const paymentMethodId = body?.paymentMethodId as string;
      if (!paymentMethodId) {
        return errorResponse('paymentMethodId is required');
      }

      const result = await getStripeCustomerId(req);
      if (result.error) return result.error;
      const { customerId } = result;

      // 校验该支付方式确实属于此 Customer（防越权）
      const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
      if (pm.customer !== customerId) {
        return errorResponse('Payment method does not belong to this customer', 403);
      }

      // Detach 会从 Customer 上解除绑定，但不删除 Stripe 记录
      await stripe.paymentMethods.detach(paymentMethodId);

      return successResponse({ success: true });
    }

    // 未匹配路由
    return errorResponse('Not found', 404);

  } catch (err) {
    console.error('manage-payment-methods error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

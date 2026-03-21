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
  const token = authHeader.replace('Bearer ', '');

  // 校验 JWT，获取当前用户
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);
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
    const url = new URL(req.url);
    // pathname 示例: /manage-payment-methods/list
    //                /manage-payment-methods/default
    //                /manage-payment-methods/pm_xxx
    const pathParts = url.pathname.split('/').filter(Boolean);
    // pathParts[0] = 'manage-payment-methods'，pathParts[1] = action/id
    const action = pathParts[1] ?? '';

    // -------------------------------------------------------
    // GET /list — 获取已保存卡片列表
    // -------------------------------------------------------
    if (req.method === 'GET' && action === 'list') {
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
      const defaultPmId = customerData.invoice_settings?.default_payment_method as string | null;

      // 格式化返回数据，只暴露必要字段
      const paymentMethods = pmList.data.map((pm) => ({
        id: pm.id,
        brand: pm.card?.brand ?? 'unknown',          // visa / mastercard / amex 等
        last4: pm.card?.last4 ?? '****',
        expMonth: pm.card?.exp_month ?? 0,
        expYear: pm.card?.exp_year ?? 0,
        isDefault: pm.id === defaultPmId,
      }));

      return successResponse({ paymentMethods });
    }

    // -------------------------------------------------------
    // POST /default — 设置默认卡
    // body: { paymentMethodId: string }
    // -------------------------------------------------------
    if (req.method === 'POST' && action === 'default') {
      const result = await getStripeCustomerId(req);
      if (result.error) return result.error;
      const { customerId } = result;

      const body = await req.json();
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

    // -------------------------------------------------------
    // DELETE /:id — 删除已保存的卡
    // -------------------------------------------------------
    if (req.method === 'DELETE' && action) {
      const paymentMethodId = action; // URL 最后一段即为 pm_xxx

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

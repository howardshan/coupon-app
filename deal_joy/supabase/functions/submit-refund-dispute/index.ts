// Edge Function: submit-refund-dispute（已废弃）
// 历史：已核销券 24h 内争议 → refund_requests。
// 现统一走 after-sales-request + after_sales_requests；此入口仅返回 410，供旧客户端识别。

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const RETIRED_BODY = JSON.stringify({
  error:
    "This flow is retired. Open After-sales from your used voucher (within 7 days of redemption) in the app.",
  code: "use_after_sales",
});

Deno.serve((_req) => {
  if (_req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(RETIRED_BODY, {
    status: 410,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

// Edge Function: submit-refund-request（已废弃）
// 历史：整单级核销后退款 → refund_requests。现已统一走 after-sales-request。

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

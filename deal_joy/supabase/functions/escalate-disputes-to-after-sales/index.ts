// 由 pg_cron 定时调用：将 pending_merchant 争议在核销满 24h 后升级为售后单（RPC）
// 依赖：CRON_SECRET 与 vault.cron_secret 一致；Dashboard Secrets 已配置

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

const CRON_SECRET = Deno.env.get('CRON_SECRET');

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (CRON_SECRET) {
    const incomingSecret = req.headers.get('x-cron-secret');
    if (incomingSecret !== CRON_SECRET) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  }

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  const { data, error } = await supabaseAdmin.rpc('escalate_pending_disputes_to_after_sales', {
    p_limit: 100,
  });

  if (error) {
    console.error('[escalate-disputes-to-after-sales]', error.message);
    return new Response(
      JSON.stringify({ error: error.message, code: error.code }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  return new Response(JSON.stringify({ ok: true, result: data }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
